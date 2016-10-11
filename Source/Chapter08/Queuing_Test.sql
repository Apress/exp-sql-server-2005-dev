--Create the SSB objects
CREATE MESSAGE TYPE Pipeline_Test_Msg
VALIDATION = EMPTY
GO

CREATE CONTRACT Pipeline_Test_Contract
(Pipeline_Test_Msg SENT BY INITIATOR)
GO

CREATE QUEUE Pipeline_Test_Queue
GO

CREATE SERVICE Pipeline_Test_Service
ON QUEUE Pipeline_Test_Queue
(Pipeline_Test_Contract)
GO




--Create the tables
CREATE TABLE Pipeline_Test_Rows
(
    AColumn INT,
    BColumn DATETIME DEFAULT(GETDATE())
)
GO

CREATE TABLE Pipeline_Test_Times
(
    StartTime DATETIME,
    EndTime DATETIME,
    NumberOfThreads INT
)
GO




--Create the activation proc
CREATE PROC Pipeline_Test_Activation
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @handle UNIQUEIDENTIFIER
    DECLARE @start datetime

    WHILE 1=1
    BEGIN
        SET @handle = NULL

        --Wait up to five seconds for a message
        WAITFOR
        (
            RECEIVE top(1) @handle = conversation_handle
            FROM Pipeline_Test_Queue
        ), TIMEOUT 5000

        --We didn't get a handle -- abort the loop
        IF @handle IS NULL
            BREAK

        SET @start = GETDATE()

        INSERT Pipeline_Test_Rows
        (
            AColumn
        )
        SELECT TOP(100)
            Number
        FROM master..spt_values

        END CONVERSATION @handle
        WITH CLEANUP

        INSERT Pipeline_Test_Times
        (
            StartTime,
            EndTime,
            NumberOfThreads
        )
        SELECT
            @start,
            GETDATE(),
            COUNT(*)
        FROM sys.dm_broker_activated_tasks
    END
END
GO




--Interim results
CREATE TABLE FinalResults
(
    AvgIterationTime INT,
    ConcurrentThreads INT
)
GO




--The actual worker loop
DECLARE @counter INT
SET @counter = 1

WHILE @counter <= 200
BEGIN
    TRUNCATE TABLE Pipeline_Test_Rows
    TRUNCATE TABLE Pipeline_Test_Times

    --Alter the queue and turn on activation
    ALTER QUEUE Simple_Queue_Target
    WITH ACTIVATION
    (
        STATUS = OFF
    )

    --Reset the database
    ALTER DATABASE Pipeline_Test SET NEW_BROKER

    DECLARE @i INT
    SET @i = 1

    WHILE @i <= 200000
    BEGIN
        DECLARE @h UNIQUEIDENTIFIER

        BEGIN DIALOG CONVERSATION @h
        FROM SERVICE Pipeline_Test_Service
        TO SERVICE 'Pipeline_Test_Service'
        ON CONTRACT Pipeline_Test_Contract
        WITH ENCRYPTION=OFF;

        SEND ON CONVERSATION @h
        MESSAGE TYPE Pipeline_Test_Msg

        SET @i = @i + 1
    END

    --Need dynamic SQL here because MAX_QUEUE_READERS cannot take
    --a variable as input
    DECLARE @sql VARCHAR(500)
    SET @sql = '' +
        'ALTER QUEUE Pipeline_Test_Queue ' +
        'WITH ACTIVATION ' +
        '( ' +
            'STATUS = ON, ' +
            'PROCEDURE_NAME = Pipeline_Test_Activation, ' +
            'MAX_QUEUE_READERS = ' + CONVERT(VARCHAR, @counter) + ', ' +
            'EXECUTE AS OWNER ' +
        ')'

    EXEC (@sql)

    --Activation has started -- wait for everything to finish
    WHILE 1=1
    BEGIN
        WAITFOR DELAY '00:00:10'

        IF
            (
                SELECT COUNT(*)
                FROM Pipeline_Test_Rows WITH (NOLOCK)
            ) = 20000000
        BEGIN
            INSERT FinalResults
            (
                AvgIterationTime,
                ConcurrentThreads
            )
            SELECT
                AVG(DATEDIFF(ms, StartTime, EndTime)),
                @counter
            FROM Pipeline_Test_Times
            WHERE NumberOfThreads = @counter

            BREAK
        END
    END

    SET @counter = @counter + 1
END
GO

