#ifndef GRINNODEMANAGER_H
#define GRINNODEMANAGER_H

#include <QObject>
#include <QProcess>
#include <QDebug>
#include <QCoreApplication>
#include <QTimer>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

#ifdef Q_OS_LINUX
#include <sys/types.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <signal.h>
#endif

class GrinNodeManager : public QObject
{
    Q_OBJECT
public:
    explicit GrinNodeManager(QObject *parent = nullptr);
    ~GrinNodeManager();

    bool startNode(QString network);
    void stopNode();
    bool isNodeRunning() const;

private:
    void setupJobObject();

    QProcess *m_nodeProcess;

    #ifdef Q_OS_WIN
    HANDLE m_jobHandle;
    #endif

    int m_pid;
};

#endif // GRINNODEMANAGER_H
