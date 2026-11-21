#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QtTest>

#include "backend.h"
#include "theme.h"
#include "translator.h"

class NvmonTests : public QObject {
    Q_OBJECT

private slots:
    void parsesAGpuLine()
    {
        const auto gpu = Backend::parseGpu(
            "NVIDIA GeForce RTX 3060, 615.78.08, 44, 31, 33.43, 170.00, P2, 3, 3, 8, 16, 139, 12288, 0, 1\n");
        QCOMPARE(gpu.value("name").toString(), QString("NVIDIA GeForce RTX 3060"));
        QCOMPARE(gpu.value("driver").toString(), QString("615.78.08"));
        QCOMPARE(gpu.value("temperature").toDouble(), 44.0);
        QCOMPARE(gpu.value("fan").toDouble(), 31.0);
        QCOMPARE(gpu.value("power").toDouble(), 33.43);
        QCOMPARE(gpu.value("pstate").toString(), QString("P2"));
        QCOMPARE(gpu.value("linkGen").toInt(), 3);
        QCOMPARE(gpu.value("linkWidth").toInt(), 8);
        QCOMPARE(gpu.value("linkWidthMax").toInt(), 16);
        QCOMPARE(gpu.value("memoryTotal").toDouble(), 12288.0);
        QCOMPARE(gpu.value("encoder").toDouble(), 1.0);
    }

    void leavesOutValuesTheCardDoesNotReport()
    {
        const auto gpu = Backend::parseGpu("Some GPU, 1.0, 40, [N/A], [N/A], 170.00, P8, 1, 3, 8, 16, 15, 12288, 0, 0");
        QVERIFY(!gpu.contains("fan"));
        QVERIFY(!gpu.contains("power"));
        QCOMPARE(gpu.value("linkGen").toInt(), 1);
    }

    void rejectsALineThatIsNotGpuData()
    {
        QVERIFY(Backend::parseGpu("Unable to determine the device handle for GPU0: GPU is lost.").isEmpty());
        QVERIFY(Backend::parseGpu("").isEmpty());
    }

    void queryFieldsMatchTheParser()
    {
        QCOMPARE(Backend::gpuQueryFields().size(), 15);
    }

    void parsesProcesses()
    {
        const auto apps = Backend::parseApps("2236, /usr/lib/voxtype/voxtype-osd-gtk4, 4\n8734, /usr/bin/ffmpeg, 116\n");
        QCOMPARE(apps.size(), 2);
        QCOMPARE(apps.at(1).toMap().value("pid").toInt(), 8734);
        QCOMPARE(apps.at(1).toMap().value("name").toString(), QString("ffmpeg"));
        QCOMPARE(apps.at(1).toMap().value("memory").toDouble(), 116.0);
        QVERIFY(Backend::parseApps("").isEmpty());
    }

    void countsXidErrors()
    {
        const QString journal =
            "2026-11-20T15:31:40-03:00 host kernel: NVRM: Xid (PCI:0000:02:00): 79, GPU has fallen off the bus.\n"
            "2026-11-20T15:31:40-03:00 host kernel: NVRM: GPU 0000:02:00.0: GPU has fallen off the bus.\n"
            "2026-11-20T15:31:41-03:00 host kernel: NVRM: Xid (PCI:0000:02:00): 154, GPU recovery action changed\n";
        int code = 0;
        QString time;
        QCOMPARE(Backend::countXids(journal, &code, &time), 2);
        QCOMPARE(code, 154);
        QCOMPARE(time, QString("2026-11-20 15:31:41"));
        QCOMPARE(Backend::countXids("-- No entries --\n"), 0);
    }

    void readsTheKeepaliveState()
    {
        QCOMPARE(Backend::parseUnitState("LoadState=loaded\nActiveState=active\n"), QString("active"));
        QCOMPARE(Backend::parseUnitState("LoadState=loaded\nActiveState=inactive\n"), QString("inactive"));
        QCOMPARE(Backend::parseUnitState("LoadState=not-found\nActiveState=inactive\n"), QString("missing"));
        QCOMPARE(Backend::parseUnitState(""), QString("missing"));
    }

    void reportsAMissingNvidiaSmi()
    {
        Backend backend(Backend::Tools{}, 60000);
        QVERIFY(backend.error().contains("nvidia-smi"));
        QVERIFY(backend.gpu().isEmpty());
    }

    void readsTheGpuThroughNvidiaSmi()
    {
        QTemporaryDir dir;
        const QString smi = script(dir, "nvidia-smi",
            "case \"$1\" in\n"
            "  --query-gpu=*) echo 'Test GPU, 1.2.3, 50, 30, 20.50, 170.00, P2, 3, 3, 8, 16, 100, 12288, 2, 0' ;;\n"
            "  *) echo '42, /usr/bin/worker, 64' ;;\n"
            "esac\n");
        const QString systemctl = script(dir, "systemctl", "printf 'LoadState=loaded\\nActiveState=active\\n'\n");
        const QString journalctl = script(dir, "journalctl", "echo '-- No entries --'; exit 1\n");

        Backend backend(Backend::Tools{smi, journalctl, systemctl}, 60000);
        QTRY_COMPARE(backend.gpu().value("name").toString(), QString("Test GPU"));
        QTRY_COMPARE(backend.apps().size(), 1);
        QTRY_COMPARE(backend.keepalive(), QString("active"));
        QCOMPARE(backend.error(), QString());
        QCOMPARE(backend.xidCount(), 0);
    }

    void reportsALostGpu()
    {
        QTemporaryDir dir;
        const QString smi = script(dir, "nvidia-smi",
            "echo 'Unable to determine the device handle for GPU0: 0000:02:00.0: GPU is lost.'; exit 15\n");
        Backend backend(Backend::Tools{smi, {}, {}}, 60000);
        QTRY_VERIFY(backend.error().contains("GPU is lost"));
        QVERIFY(backend.gpu().isEmpty());
    }

    void themeFallsBack()
    {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QString("black"));
    }

    void themeReadsAccent()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("theme");
        write(dir.path() + "/theme/colors.toml", "accent = \"#112233\"\n");

        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#112233"));
        QCOMPARE(theme.accentForeground(), QString("white"));
    }

    void themeFollowsHyprlandRounding()
    {
        QTemporaryDir dir;
        const QString response = dir.filePath("response.json");
        const QString command = script(dir, "hyprctl", "cat '" + response.toUtf8() + "'\n");
        write(response, "{\"int\":0}");

        Theme theme(dir.path(), nullptr, command);
        QCOMPARE(theme.radius(), 0);
        write(response, "{\"int\":6}");
        QTRY_COMPARE(theme.radius(), 6);
    }

    void translatorFallsBackToEnglish()
    {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Fan").isNull());
    }

    void translatorFollowsTheLanguageFile()
    {
        QTemporaryDir dir;
        write(dir.path() + "/language", "pt-BR\n");
        write(dir.path() + "/pt.json", R"({"Fan": "Ventoinha", "Power": "Consumo"})");
        write(dir.path() + "/pt-BR.json", R"({"Fan": "Ventilador"})");

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("pt-BR"));
        QCOMPARE(translator.translate("Main", "Fan"), QString("Ventilador"));
        QCOMPARE(translator.translate("Main", "Power"), QString("Consumo"));
        QVERIFY(translator.translate("Main", "Quit").isNull());
    }

    void shippedPortugueseCatalogIsValid()
    {
        QFile catalog(QFINDTESTDATA("../src/i18n/pt.json"));
        QVERIFY(catalog.open(QIODevice::ReadOnly));
        const auto document = QJsonDocument::fromJson(catalog.readAll());
        QVERIFY(document.isObject());
        QVERIFY(document.object().contains("Fan"));
    }

private:
    static void write(const QString &path, const QByteArray &contents)
    {
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(contents);
    }

    static QString script(const QTemporaryDir &dir, const QString &name, const QByteArray &body)
    {
        const QString path = dir.filePath(name);
        QFile file(path);
        if (!file.open(QIODevice::WriteOnly))
            return {};
        file.write("#!/bin/sh\n" + body);
        file.close();
        QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        return path;
    }
};

QTEST_MAIN(NvmonTests)
#include "nvmon_tests.moc"
