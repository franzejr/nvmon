#include "backend.h"

#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

Backend::Tools Backend::Tools::system() {
    return {QStandardPaths::findExecutable("nvidia-smi"), QStandardPaths::findExecutable("journalctl"),
            QStandardPaths::findExecutable("systemctl")};
}

Backend::Backend(const Tools &tools, int intervalMs, QObject *parent) : QObject(parent), m_tools(tools) {
    m_timer.setInterval(intervalMs);
    connect(&m_timer, &QTimer::timeout, this, &Backend::refresh);
    m_timer.start();
    refresh();
}

// Quitting mid-poll must not leave a query running or call back into a
// half-destroyed object.
Backend::~Backend() {
    const auto processes = findChildren<QProcess *>();
    for (QProcess *process : processes) {
        process->disconnect(this);
        if (process->state() != QProcess::NotRunning) {
            process->kill();
            process->waitForFinished(500);
        }
    }
}

// One short-lived process per query. A GPU that has fallen off the bus can
// make nvidia-smi hang, so every run is killed after a few seconds.
void Backend::run(const QString &program, const QStringList &arguments, Done done) {
    auto *process = new QProcess(this);
    auto *timeout = new QTimer(process);
    timeout->setSingleShot(true);
    timeout->setInterval(4000);
    connect(timeout, &QTimer::timeout, process, &QProcess::kill);
    connect(process, &QProcess::errorOccurred, this, [process, done](QProcess::ProcessError error) {
        // Crashes and kills are followed by finished(); only a failed start is not.
        if (error != QProcess::FailedToStart)
            return;
        done(false, {}, process->errorString());
        process->deleteLater();
    });
    connect(process, &QProcess::finished, this, [process, done](int code, QProcess::ExitStatus status) {
        done(code == 0 && status == QProcess::NormalExit, QString::fromUtf8(process->readAllStandardOutput()),
             QString::fromUtf8(process->readAllStandardError()));
        process->deleteLater();
    });
    process->start(program, arguments);
    timeout->start();
}

void Backend::refresh() {
    pollGpu();
    // The journal and the service change rarely; ask every fifth tick.
    if (m_tick++ % 5 == 0)
        pollSystem();
}

QStringList Backend::gpuQueryFields() {
    return {"name", "driver_version", "temperature.gpu", "fan.speed", "power.draw", "power.limit", "pstate",
            "pcie.link.gen.current", "pcie.link.gen.max", "pcie.link.width.current", "pcie.link.width.max",
            "memory.used", "memory.total", "utilization.gpu", "utilization.encoder"};
}

// One CSV line from nvidia-smi, in gpuQueryFields() order. A value the card
// doesn't report ("[N/A]") is left out of the map, so QML shows a dash.
QVariantMap Backend::parseGpu(const QString &csvLine) {
    static const QStringList keys{"name", "driver", "temperature", "fan", "power", "powerLimit", "pstate",
                                  "linkGen", "linkGenMax", "linkWidth", "linkWidthMax",
                                  "memoryUsed", "memoryTotal", "utilization", "encoder"};
    const QStringList values = csvLine.trimmed().split(", ");
    QVariantMap gpu;
    if (values.size() != keys.size())
        return gpu;
    for (int i = 0; i < keys.size(); ++i) {
        const QString value = values.at(i).trimmed();
        if (value.isEmpty() || value.startsWith('['))
            continue;
        if (i < 2 || keys.at(i) == "pstate") {
            gpu.insert(keys.at(i), value);
            continue;
        }
        bool ok = false;
        const double number = value.toDouble(&ok);
        if (ok)
            gpu.insert(keys.at(i), number);
    }
    return gpu;
}

// Lines of "pid, process name, used memory in MiB".
QVariantList Backend::parseApps(const QString &csv) {
    QVariantList apps;
    for (const QString &line : csv.split('\n', Qt::SkipEmptyParts)) {
        const QStringList values = line.trimmed().split(", ");
        if (values.size() != 3)
            continue;
        bool ok = false;
        const int pid = values.at(0).toInt(&ok);
        if (!ok)
            continue;
        const QString path = values.at(1).trimmed();
        apps.append(QVariantMap{{"pid", pid}, {"name", path.section('/', -1)}, {"memory", values.at(2).toDouble()}});
    }
    return apps;
}

// Kernel journal lines in short-iso format. Each NVRM Xid line is one error.
int Backend::countXids(const QString &journal, int *lastCode, QString *lastTime) {
    static const QRegularExpression expression(R"re(^(\S+) .*NVRM: Xid \([^)]*\): (\d+))re",
                                               QRegularExpression::MultilineOption);
    int count = 0;
    auto matches = expression.globalMatch(journal);
    while (matches.hasNext()) {
        const auto match = matches.next();
        ++count;
        if (lastCode)
            *lastCode = match.captured(2).toInt();
        if (lastTime)
            *lastTime = match.captured(1).left(19).replace('T', ' ');
    }
    return count;
}

// Output of "systemctl show -p LoadState -p ActiveState".
QString Backend::parseUnitState(const QString &showOutput) {
    QString load, active;
    for (const QString &line : showOutput.split('\n', Qt::SkipEmptyParts)) {
        if (line.startsWith("LoadState="))
            load = line.mid(10).trimmed();
        else if (line.startsWith("ActiveState="))
            active = line.mid(12).trimmed();
    }
    if (load != "loaded" || active.isEmpty())
        return "missing";
    return active;
}

void Backend::pollGpu() {
    if (m_gpuBusy)
        return;
    if (m_tools.nvidiaSmi.isEmpty()) {
        const QString error = tr("nvidia-smi was not found. Install the NVIDIA driver utilities.");
        if (error != m_error || !m_gpu.isEmpty()) {
            m_error = error;
            m_gpu.clear();
            m_apps.clear();
            emit changed();
        }
        return;
    }
    m_gpuBusy = true;
    run(m_tools.nvidiaSmi, {"--query-gpu=" + gpuQueryFields().join(','), "--format=csv,noheader,nounits", "--id=0"},
        [this](bool ok, const QString &out, const QString &err) {
            const QVariantMap gpu = ok ? parseGpu(out.section('\n', 0, 0)) : QVariantMap();
            if (gpu.isEmpty()) {
                // nvidia-smi explains a lost or missing GPU on stdout.
                const QString reason = (out.trimmed().isEmpty() ? err : out).trimmed().section('\n', 0, 0);
                m_error = reason.isEmpty() ? tr("nvidia-smi did not answer. The GPU may have fallen off the bus.")
                                           : tr("nvidia-smi failed: %1").arg(reason);
                m_gpu.clear();
                m_apps.clear();
                m_gpuBusy = false;
                emit changed();
                return;
            }
            m_error.clear();
            m_gpu = gpu;
            run(m_tools.nvidiaSmi,
                {"--query-compute-apps=pid,name,used_memory", "--format=csv,noheader,nounits", "--id=0"},
                [this](bool ok, const QString &out, const QString &) {
                    if (ok)
                        m_apps = parseApps(out);
                    m_gpuBusy = false;
                    emit changed();
                });
        });
}

void Backend::pollSystem() {
    if (m_systemBusy)
        return;
    m_systemBusy = true;
    auto readService = [this] {
        if (m_tools.systemctl.isEmpty()) {
            m_systemBusy = false;
            return;
        }
        run(m_tools.systemctl, {"--user", "show", "-p", "LoadState", "-p", "ActiveState", KeepaliveUnit},
            [this](bool, const QString &out, const QString &) {
                m_keepalive = parseUnitState(out);
                m_systemBusy = false;
                emit changed();
            });
    };
    if (m_tools.journalctl.isEmpty()) {
        readService();
        return;
    }
    // journalctl exits 1 when nothing matches, which simply means no errors.
    run(m_tools.journalctl, {"-k", "-b", "0", "--no-pager", "-o", "short-iso", "-g", "NVRM: Xid"},
        [this, readService](bool, const QString &out, const QString &) {
            int code = 0;
            QString time;
            m_xidCount = countXids(out, &code, &time);
            m_lastXidCode = code;
            m_lastXidTime = time;
            emit changed();
            readService();
        });
}

void Backend::toggleKeepalive() {
    if (m_tools.systemctl.isEmpty() || m_keepalive == "missing")
        return;
    const QString verb = m_keepalive == "active" || m_keepalive == "activating" ? "stop" : "start";
    run(m_tools.systemctl, {"--user", verb, KeepaliveUnit}, [this](bool, const QString &, const QString &) {
        m_systemBusy = false;
        pollSystem();
    });
}
