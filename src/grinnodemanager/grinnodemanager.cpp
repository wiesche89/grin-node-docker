#include "grinnodemanager.h"

/**
 * @brief GrinNodeManager::GrinNodeManager
 * @param parent
 */
GrinNodeManager::GrinNodeManager(QObject *parent) :
    QObject(parent),
    m_nodeProcess(new QProcess(this)),
    m_pid(-1)
{
    #ifdef Q_OS_WIN
    m_jobHandle = nullptr;
    #endif

    setupJobObject();

    connect(qApp, &QCoreApplication::aboutToQuit, this, &GrinNodeManager::stopNode);

    connect(m_nodeProcess, &QProcess::readyReadStandardOutput, [this]() {
        QStringList stdOut = QString::fromUtf8(m_nodeProcess->readAllStandardOutput()).split("\r\n");

        for (int i = 0; i < stdOut.length(); i++) {
            qDebug() << stdOut[i];
        }
    });

    connect(m_nodeProcess, &QProcess::readyReadStandardError, [this]() {
        QStringList stdOut = QString::fromUtf8(m_nodeProcess->readAllStandardOutput()).split("\r\n");

        for (int i = 0; i < stdOut.length(); i++) {
            qDebug() << stdOut[i];
        }
    });
}

/**
 * @brief GrinNodeManager::~GrinNodeManager
 */
GrinNodeManager::~GrinNodeManager()
{
    stopNode();

    #ifdef Q_OS_WIN
    if (m_jobHandle) {
        CloseHandle(m_jobHandle);
        m_jobHandle = nullptr;
    }
    #elif defined(Q_OS_LINUX)
    // Unter Linux ist kein Handle zu schließen
    qInfo() << "No job object cleanup required on Linux.";
    #endif
}

/**
 * @brief GrinNodeManager::setupJobObject
 */
void GrinNodeManager::setupJobObject()
{
#ifdef Q_OS_WIN
    m_jobHandle = CreateJobObject(nullptr, nullptr);
    if (m_jobHandle == nullptr) {
        qWarning() << "CreateJobObject failed:" << GetLastError();
        return;
    }

    // Set up the job object to kill all child processes when the job is closed
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION jeli = {};
    jeli.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

    if (!SetInformationJobObject(m_jobHandle, JobObjectExtendedLimitInformation, &jeli, sizeof(jeli))) {
        qWarning() << "SetInformationJobObject failed:" << GetLastError();
        CloseHandle(m_jobHandle);
        m_jobHandle = nullptr;
    }
#elif defined(Q_OS_LINUX)
    // Linux: nothing to initialize here, but we can log it
    qInfo() << "Job object setup not required on Linux.";
#endif
}

/**
 * @brief GrinNodeManager::startNode
 */
bool GrinNodeManager::startNode(QString network)
{
    if (isNodeRunning()) {
        qCritical() << "Node process already running.";
        return false;
    }

    QString program;

    #ifdef Q_OS_WIN
    program = "grin";
    #else
    program = "./grin";
    #endif

    if (network == "test") {
        m_nodeProcess->start(program, {"--testnet"});
    } else if (network == "main") {
        m_nodeProcess->start(program);
    } else {
        qDebug() << "network is undefined!";
        return false;
    }

    if (!m_nodeProcess->waitForStarted(3000)) {
        qCritical() << "Error: grin process could not be started.";
        return false;
    }

    qDebug() << "waitForStarted success ";

#ifdef Q_OS_WIN
    HANDLE processHandle = (HANDLE)m_nodeProcess->processId();
    if (m_jobHandle && processHandle) {
        HANDLE hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, m_nodeProcess->processId());
        if (hProcess) {
            if (!AssignProcessToJobObject(m_jobHandle, hProcess)) {
                qWarning() << "AssignProcessToJobObject failed:" << GetLastError();
            }
            CloseHandle(hProcess);
        } else {
            qWarning() << "OpenProcess failed:" << GetLastError();
        }
    }
#elif defined(Q_OS_LINUX)
    pid_t pid = m_nodeProcess->processId();
    if (pid > 0) {
        // Set child to new process group so it can be killed later with killpg
        if (setpgid(pid, pid) != 0) {
            perror("setpgid failed");
        }
        // Optional: ensure child dies with parent
        if (prctl(PR_SET_PDEATHSIG, SIGTERM) != 0) {
            perror("prctl(PR_SET_PDEATHSIG) failed");
        }
    }
#endif

    m_pid = m_nodeProcess->processId();
    qDebug() << "grin started, PID:" << m_pid;

    QTimer *monitorTimer = new QTimer(this);
    QObject::connect(monitorTimer, &QTimer::timeout, [&]() {
        if (m_nodeProcess->processId() != m_pid) {
            qDebug() << "grin process was terminated.";
            monitorTimer->stop();
            QCoreApplication::quit();
        }
    });
    monitorTimer->start(1000);

    return true;
}

/**
 * @brief GrinNodeManager::stopNode
 */
void GrinNodeManager::stopNode()
{
    if (!isNodeRunning()) {
        return;
    }

    qDebug() << "Close grin...";

    m_nodeProcess->terminate();
    if (!m_nodeProcess->waitForFinished(3000)) {
        qDebug() << "Process does not respond, force kill.";
        m_nodeProcess->kill();
        m_nodeProcess->waitForFinished(3000);
    }
}

/**
 * @brief GrinNodeManager::isNodeRunning
 * @return
 */
bool GrinNodeManager::isNodeRunning() const
{
    return m_nodeProcess->state() != QProcess::NotRunning;
}
