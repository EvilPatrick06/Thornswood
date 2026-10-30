// The Qt 6 prototype for the launcher stack study (#3209): Qt Quick drawn by
// Qt's own scene graph. README.md has the contract every prototype keeps.
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QProcess>
#include <QQmlContext>
#include <QQuickView>
#include <QTimer>
#include <QUrl>
#ifdef Q_OS_WIN
#include <windows.h>
#include <mmsystem.h>
#endif

static void writeFlag(const QString &suffix, const char *text)
{
    QString f = qEnvironmentVariable("PROTO_READY");
    if (f.isEmpty()) return;
    QFile out(f + suffix);
    if (out.open(QIODevice::WriteOnly)) out.write(text);
}

class Proto : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
public:
    QString state() const { return m_state; }
    Q_INVOKABLE void play()
    {
#ifdef Q_OS_WIN
        QString wav = QDir(QCoreApplication::applicationDirPath()).filePath("loop.wav");
        PlaySoundW(reinterpret_cast<LPCWSTR>(QDir::toNativeSeparators(wav).utf16()), nullptr, SND_ASYNC | SND_LOOP | SND_FILENAME);
        qint64 pid = 0;
        QProcess::startDetached("cmd.exe", {"/c", "exit", "0"}, QString(), &pid);
#else
        qint64 pid = 0;
        QProcess::startDetached("true", {}, QString(), &pid);
#endif
        m_state = QString("Started %1").arg(pid);
        emit stateChanged();
        writeFlag(".active", "active");
    }
signals:
    void stateChanged();
private:
    QString m_state = "Ready to launch";
};

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    Proto proto;
    QQuickView view;
    view.setTitle("Thornswood qt");
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.rootContext()->setContextProperty("proto", &proto);
    view.rootContext()->setContextProperty("artUrl", QUrl::fromLocalFile(QDir(QCoreApplication::applicationDirPath()).filePath("art.png")));
    view.setSource(QUrl("qrc:/Main.qml"));
    QObject::connect(&view, &QQuickWindow::frameSwapped, &view, [&]() {
        static bool fired = false;
        if (fired) return;
        fired = true;
        writeFlag("", "ready");
        QTimer::singleShot(4000, &proto, &Proto::play);
    });
    view.resize(1220, 800);
    view.show();
    return app.exec();
}

#include "main.moc"
