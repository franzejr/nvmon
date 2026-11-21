#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

// Polls nvidia-smi for the state of the first NVIDIA GPU, the kernel journal
// for Xid errors in this boot, and systemd for the keepalive service that
// holds the card out of its idle state.
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap gpu READ gpu NOTIFY changed)
    Q_PROPERTY(QVariantList apps READ apps NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(int xidCount READ xidCount NOTIFY changed)
    Q_PROPERTY(int lastXidCode READ lastXidCode NOTIFY changed)
    Q_PROPERTY(QString lastXidTime READ lastXidTime NOTIFY changed)
    Q_PROPERTY(QString keepalive READ keepalive NOTIFY changed)

public:
    // The command-line tools the backend runs. Tests point these at scripts.
    struct Tools {
        QString nvidiaSmi, journalctl, systemctl;
        static Tools system();
    };

    explicit Backend(const Tools &tools, int intervalMs = 2000, QObject *parent = nullptr);
    ~Backend() override;

    QVariantMap gpu() const { return m_gpu; }
    QVariantList apps() const { return m_apps; }
    QString error() const { return m_error; }
    int xidCount() const { return m_xidCount; }
    int lastXidCode() const { return m_lastXidCode; }
    QString lastXidTime() const { return m_lastXidTime; }
    // "active", "inactive", "failed", ... from systemd, or "missing" when the
    // unit isn't installed.
    QString keepalive() const { return m_keepalive; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void toggleKeepalive();

    static QStringList gpuQueryFields();
    static QVariantMap parseGpu(const QString &csvLine);
    static QVariantList parseApps(const QString &csv);
    static int countXids(const QString &journal, int *lastCode = nullptr, QString *lastTime = nullptr);
    static QString parseUnitState(const QString &showOutput);

    static constexpr const char *KeepaliveUnit = "rtx-keepalive.service";

signals:
    void changed();

private:
    using Done = std::function<void(bool ok, const QString &out, const QString &err)>;
    void run(const QString &program, const QStringList &arguments, Done done);
    void pollGpu();
    void pollSystem();

    Tools m_tools;
    QTimer m_timer;
    int m_tick = 0;
    bool m_gpuBusy = false, m_systemBusy = false;

    QVariantMap m_gpu;
    QVariantList m_apps;
    QString m_error;
    int m_xidCount = 0, m_lastXidCode = 0;
    QString m_lastXidTime;
    QString m_keepalive = "missing";
};
