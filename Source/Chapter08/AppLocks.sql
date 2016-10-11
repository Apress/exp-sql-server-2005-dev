--Take and release an application lock
BEGIN TRAN

DECLARE @ReturnValue INT

EXEC @ReturnValue = sp_getapplock
    @Resource = 'customers',
    @LockMode = 'exclusive',
    @LockTimeout = 2000

IF @ReturnValue IN (0, 1)
    PRINT 'Lock granted'
ELSE
    PRINT 'Lock not granted'

EXEC sp_releaseapplock
    @Resource = 'customers'

COMMIT
GO



--AppLocks table
CREATE TABLE AppLocks
(
    AppLockName NVARCHAR(255) NOT NULL,
    AppLockKey UNIQUEIDENTIFIER NULL,
    InitiatorDialogHandle UNIQUEIDENTIFIER NOT NULL,
    TargetDialogHandle UNIQUEIDENTIFIER NOT NULL,
    LastGrantedDate DATETIME NOT NULL DEFAULT(GETDATE()),
    PRIMARY KEY (AppLockName)
)
GO




--Message and contract
CREATE MESSAGE TYPE AppLockGrant
VALIDATION=EMPTY
GO

CREATE CONTRACT AppLockContract (
    AppLockGrant SENT BY INITIATOR
)
GO





--Queues and services
CREATE QUEUE AppLock_Queue
GO

CREATE SERVICE AppLock_Service
ON QUEUE AppLock_Queue (AppLockContract)
GO

CREATE QUEUE AppLockTimeout_Queue
GO

CREATE SERVICE AppLockTimeout_Service
ON QUEUE AppLockTimeOut_Queue
GO





--The GetAppLock proc
CREATE PROC GetAppLock
    @AppLockName NVARCHAR(255),
    @LockTimeout INT,
    @AppLockKey UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON

    --Make sure this variable starts NULL
    SET @AppLockKey = NULL

    DECLARE @LOCK_TIMEOUT_LIFETIME INT
    SET @LOCK_TIMEOUT_LIFETIME = 18000 --5 hours

    DECLARE @startWait DATETIME
    SET @startWait = GETDATE()

    DECLARE @init_handle UNIQUEIDENTIFIER
    DECLARE @target_handle UNIQUEIDENTIFIER

    BEGIN TRAN

    --Get the app lock -- start waiting
    DECLARE @RETURN int
    EXEC @RETURN = sp_getapplock
        @resource = @AppLockName,
        @lockmode = 'exclusive',
        @LockTimeout = @LockTimeout

    IF @RETURN NOT IN (0, 1)
    BEGIN
        RAISERROR(
             'Error acquiring transactional lock for %s', 16, 1, @AppLockName)
        ROLLBACK
        RETURN
    END

    --Find out whether someone has requested this lock before
    SELECT
        @target_handle = TargetDialogHandle
    FROM AppLocks
    WHERE AppLockName = @AppLockName

    --If we're here, we have the transactional lock
    IF @target_handle IS NOT NULL
    BEGIN
        --Find out whether the timeout has already expired...
        SET @LockTimeout = @LockTimeout - DATEDIFF(ms, @startWait, GETDATE())

        IF @LockTimeout > 0
        BEGIN
            --Wait for the OK message
            DECLARE @message_type NVARCHAR(255)

            --Wait for a grant message
            WAITFOR
            (
                RECEIVE
                    @message_type = message_type_name
                FROM AppLock_Queue
                WHERE conversation_handle = @target_handle
            ), TIMEOUT @LockTimeout

            IF @message_type = 'AppLockGrant'
            BEGIN
                BEGIN DIALOG CONVERSATION @AppLockKey
                FROM SERVICE AppLockTimeout_Service
                TO SERVICE 'AppLockTimeout_Service'
                WITH
                    LIFETIME = @LOCK_TIMEOUT_LIFETIME,
                    ENCRYPTION = OFF

                UPDATE AppLocks
                SET
                    AppLockKey = @AppLockKey,
                    LastGrantedDate = GETDATE()
                WHERE
                    AppLockName = @AppLockName
            END
            ELSE IF @message_type IS NOT NULL
            BEGIN
                RAISERROR('Unexpected message type: %s', 16, 1, @message_type)
                ROLLBACK
            END
        END
    END
    ELSE
    BEGIN
        --No one has requested this lock before
        ;BEGIN DIALOG @init_handle
        FROM SERVICE AppLock_Service
        TO SERVICE 'AppLock_Service'
        ON CONTRACT AppLockContract
        WITH ENCRYPTION = OFF

        --Send a throwaway message to start the dialog on both ends
        ;SEND ON CONVERSATION @init_handle
        MESSAGE TYPE AppLockGrant;

        --Get the remote handle
        SELECT
            @target_handle = ce2.conversation_handle
        FROM sys.conversation_endpoints ce1
        JOIN sys.conversation_endpoints ce2 ON
            ce1.conversation_id = ce2.conversation_id
        WHERE
            ce1.conversation_handle = @init_handle
            AND ce2.is_initiator = 0

        --Receive the throwaway message
        ;RECEIVE
            @target_handle = conversation_handle
        FROM AppLock_Queue
        WHERE conversation_handle = @target_handle

        BEGIN DIALOG CONVERSATION @AppLockKey
        FROM SERVICE AppLockTimeout_Service
        TO SERVICE 'AppLockTimeout_Service'
        WITH
            LIFETIME = @LOCK_TIMEOUT_LIFETIME,
            ENCRYPTION = OFF

        INSERT AppLocks
        (
            AppLockName,
            AppLockKey,
            InitiatorDialogHandle,
            TargetDialogHandle
        )
        VALUES
        (
            @AppLockName,
            @AppLockKey,
            @init_handle,
            @target_handle
        )
    END

    IF @AppLockKey IS NOT NULL
        COMMIT
    ELSE
    BEGIN
        RAISERROR(
            'Timed out waiting for lock on resource: %s', 16, 1, @AppLockName)
        ROLLBACK
    END
END
GO





--ReleaseAppLock proc
CREATE PROC ReleaseAppLock
    @AppLockKey UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON

    BEGIN TRAN

    DECLARE @dialog_handle UNIQUEIDENTIFIER

    UPDATE AppLocks
    SET
        AppLockKey = NULL,
        @dialog_handle = InitiatorDialogHandle
    WHERE
        AppLockKey = @AppLockKey

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('AppLockKey not found', 16, 1)
        ROLLBACK
    END

    ;END CONVERSATION @AppLockKey

    --Allow another caller to acquire the lock
    ;SEND ON CONVERSATION @dialog_handle
    MESSAGE TYPE AppLockGrant

    COMMIT
END
GO





--Activation proc
CREATE PROC AppLockTimeout_Activation
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON

    DECLARE @dialog_handle UNIQUEIDENTIFIER

    WHILE 1=1
    BEGIN
        SET @dialog_handle = NULL

        BEGIN TRAN

        WAITFOR
        (
            RECEIVE @dialog_handle = conversation_handle
            FROM AppLockTimeout_Queue
        ), TIMEOUT 10000

        IF @dialog_handle IS NOT NULL
        BEGIN
            EXEC ReleaseAppLock @AppLockKey = @dialog_handle
        END

        COMMIT
    END
END
GO

ALTER QUEUE AppLockTimeout_Queue
WITH ACTIVATION
(
    STATUS = ON,
    PROCEDURE_NAME = AppLockTimeout_Activation,
    MAX_QUEUE_READERS = 1,
    EXECUTE AS OWNER
)
GO





--Trying to take an applock with the new code
DECLARE @AppLockKey UNIQUEIDENTIFIER
EXEC GetAppLock
    @AppLockName = 'customers',
    @LockTimeout = 2000,
    @AppLockKey = @AppLockKey OUTPUT
GO


