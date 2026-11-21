#pragma once

#include <QHash>
#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

// Polls nvidia-smi for the state of the first NVIDIA GPU, the kernel journal
// for Xid errors in this boot, and systemd for the keepalive service that
// holds the card out of its idle state. Keeps a few minutes of history so the
// window can show whether the PCIe link has been dropping to its idle speed.
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap gpu READ gpu NOTIFY changed)
    Q_PROPERTY(QVariantList apps READ apps NOTIFY changed)
    Q_PROPERTY(QVariantMap history READ history NOTIFY changed)
    Q_PROPERTY(int historySize READ historySize CONSTANT)
    Q_PROPERTY(int intervalMs READ intervalMs CONSTANT)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(int xidCount READ xidCount NOTIFY changed)
    Q_PROPERTY(int lastXidCode READ lastXidCode NOTIFY changed)
    Q_PROPERTY(QString lastXidTime READ lastXidTime NOTIFY changed)
    Q_PROPERTY(double stableSince READ stableSince NOTIFY changed)
    Q_PROPERTY(QString keepalive READ keepalive NOTIFY changed)
    Q_PROPERTY(double keepaliveSince READ keepaliveSince NOTIFY changed)

public:
    // The command-line tools and files the backend reads. Tests point these at
    // scripts and temp files.
    struct Tools {
        QString nvidiaSmi, journalctl, systemctl;
        QString uptimeFile = "/proc/uptime";
        static Tools system();
    };

    explicit Backend(const Tools &tools, int intervalMs = 2000, QObject *parent = nullptr);
    ~Backend() override;

    QVariantMap gpu() const { return m_gpu; }
    QVariantList apps() const { return m_apps; }
    QVariantMap history() const;
    int historySize() const { return HistorySize; }
    int intervalMs() const { return m_timer.interval(); }
    QString error() const { return m_error; }
    int xidCount() const { return m_xidCount; }
    int lastXidCode() const { return m_lastXidCode; }
    QString lastXidTime() const { return m_lastXidTime; }
    // When the GPU last came up clean, in milliseconds since the epoch: the
    // last Xid of this boot, or the boot itself. Zero when unknown.
    double stableSince() const { return m_stableSince; }
    // "active", "inactive", "failed", ... from systemd, or "missing" when the
    // unit isn't installed.
    QString keepalive() const { return m_keepalive; }
    // When the keepalive last started, in milliseconds since the epoch, or zero.
    double keepaliveSince() const { return m_keepaliveSince; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void startKeepalive();
    Q_INVOKABLE void stopKeepalive();

    static QStringList gpuQueryFields();
    static QVariantMap parseGpu(const QString &csvLine);
    static QVariantList parseApps(const QString &csv);
    static int countXids(const QString &journal, int *lastCode = nullptr, QString *lastTime = nullptr,
                         qint64 *lastEpochMs = nullptr);
    static QString parseUnitState(const QString &showOutput);
    static qint64 parseUnitStartMonotonicUs(const QString &showOutput);
    static qint64 bootEpochMs(const QString &uptimeFile, qint64 nowMs);

    static constexpr const char *KeepaliveUnit = "rtx-keepalive.service";
    // Five minutes at the default two-second interval.
    static constexpr int HistorySize = 150;
    // The series the window draws, each a list of up to HistorySize numbers.
    static QStringList historyKeys();

signals:
    void changed();

private:
    using Done = std::function<void(bool ok, const QString &out, const QString &err)>;
    void run(const QString &program, const QStringList &arguments, Done done);
    void pollGpu();
    void pollSystem();
    void controlKeepalive(const QString &verb);
    void record(const QVariantMap &gpu);

    Tools m_tools;
    QTimer m_timer;
    int m_tick = 0;
    bool m_gpuBusy = false, m_systemBusy = false;

    QVariantMap m_gpu;
    QVariantList m_apps;
    QHash<QString, QList<double>> m_history;
    QString m_error;
    int m_xidCount = 0, m_lastXidCode = 0;
    QString m_lastXidTime;
    double m_stableSince = 0;
    QString m_keepalive = "missing";
    double m_keepaliveSince = 0;
};
