USE AdventureWorks
GO

--Create a table to represent the locks
CREATE TABLE CustomerLocks
(
    CustomerId INT NOT NULL PRIMARY KEY
        REFERENCES Sales.Customer (CustomerId),
    IsLocked BIT NOT NULL DEFAULT (0)
)
GO

--Insert all of the customer IDs...
INSERT CustomerLocks
(
	CustomerId
)
SELECT CustomerId
FROM Sales.Customer
GO



--Need a lock?  Take it!
DECLARE @CustomerId INT
SET @CustomerId = 123

DECLARE @LockAcquired BIT
SET @LockAcquired = 0

IF 
    (
        SELECT IsLocked 
        FROM CustomerLocks 
        WHERE CustomerId = @CustomerId
    ) = 0
BEGIN
    UPDATE CustomerLocks
    SET IsLocked = 1
    WHERE CustomerId = @CustomerId

    SET @LockAcquired = 1
END

SELECT @LockAcquired AS Lock_Acquired
GO


--To release the lock, re-update the row
DECLARE @CustomerId INT
SET @CustomerId = 123

UPDATE CustomerLocks
SET IsLocked = 0
WHERE CustomerId = @CustomerId
GO





--Problem #1:
--Multiple issues of the same lock
--Fix: Use the WHERE clause...
DECLARE @CustomerId INT
SET @CustomerId = 123

DECLARE @LockAcquired BIT

UPDATE CustomerLocks
SET IsLocked = 1
WHERE 
    CustomerId = @CustomerId
    AND IsLocked = 0

--Did we get the lock?
SET @LockAcquired = @@ROWCOUNT

SELECT @LockAcquired AS Lock_Acquired
GO





--Problem #2:
--Maintenance. Will the CustomerLocks
--always be up to date?
--Fix: Model the locks as rows...
DROP TABLE CustomerLocks
GO

CREATE TABLE CustomerLocks
(
    CustomerId INT NOT NULL PRIMARY KEY
        REFERENCES Sales.Customer (CustomerId)
)
GO



--To take the lock now, we do an insert
DECLARE @CustomerId INT
SET @CustomerId = 123

DECLARE @LockAcquired BIT

BEGIN TRY
    INSERT CustomerLocks
    (
        CustomerId
    )
    VALUES 
    (
        @CustomerId
    )

    --No exception: Lock acquired
    SET @LockAcquired = 1
END TRY
BEGIN CATCH
    --Caught an exception: No lock acquired
    SET @LockAcquired = 0
END CATCH

SELECT @LockAcquired AS Lock_Acquired
GO

--Only one row in the locks table
SELECT *
FROM CustomerLocks
GO



--Problem #3:
--Buggy code?
--Code not following the rules?
--Fix: Lock tokens
DROP TABLE CustomerLocks
GO

CREATE TABLE CustomerLocks
(
    CustomerId INT NOT NULL PRIMARY KEY
        REFERENCES Sales.Customer (CustomerId),
    LockToken UNIQUEIDENTIFIER NOT NULL UNIQUE 
)
GO


--Taking a lock still requires an INSERT...
--This time, the routine sends a GUID back
--to the caller
DECLARE @CustomerId INT
SET @CustomerId = 123

DECLARE @LockToken UNIQUEIDENTIFIER

BEGIN TRY
    --Generate the token
    SET @LockToken = NEWID()

    INSERT CustomerLocks
    (
        CustomerId,
        LockToken
    )
    VALUES 
    (
        @CustomerId,
        @LockToken
    )
END TRY
BEGIN CATCH
    --Caught an exception: No lock acquired
    SET @LockToken = NULL
END CATCH

SELECT @LockToken AS Lock_Token
GO


--Get the token we just inserted
DECLARE @LockToken UNIQUEIDENTIFIER
SELECT @LockToken = LockToken
FROM CustomerLocks

--Now, to remove the lock, things are a bit
--different; use the token...
DELETE FROM CustomerLocks
WHERE LockToken = @LockToken
GO



--Even better:
--Tell the caller if the token wasn't found
DECLARE @LockToken UNIQUEIDENTIFIER
SELECT @LockToken = LockToken
FROM CustomerLocks

DELETE FROM CustomerLocks
WHERE LockToken = @LockToken

IF @@ROWCOUNT = 0
    RAISERROR('Lock token not found!', 16, 1)
GO

--Now if the caller sees an error it can take
--appropriate action (such as rolling back the tran)




--Problem #4:
--The "vacation" problem
--Fix: Keep the lock granted date around
DROP TABLE CustomerLocks
GO

CREATE TABLE CustomerLocks
(
    CustomerId INT NOT NULL PRIMARY KEY
        REFERENCES Sales.Customer (CustomerId),
    LockToken UNIQUEIDENTIFIER NOT NULL UNIQUE,
    LockGrantedDate DATETIME NOT NULL
        DEFAULT (GETDATE())
)
GO


--Every once in a while, fix "expired" locks
DELETE FROM CustomerLocks
WHERE LockGrantedDate < DATEADD(hour, -5, GETDATE())
GO


DECLARE @LockToken UNIQUEIDENTIFIER

--Need more time?
--Send a "heartbeat" notification
UPDATE CustomerLocks
SET LockGrantedDate = GETDATE()
WHERE LockToken = @LockToken
GO



--Problem #5:
--Programmatic locks aren't enforced
--Fix: Enforce them!

--First, add a new candidate key to the locks table
ALTER TABLE CustomerLocks
ADD CONSTRAINT UN_Customer_Token 
    UNIQUE (CustomerId, LockToken)
GO


--Next add a nullable LockToken column
--and an FK constraint to the Customer
--table...
--
--Only CustomerId/LockToken combos that actually
--exist can be inserted!
ALTER TABLE Sales.Customer
ADD
    LockToken UNIQUEIDENTIFIER NULL,
    CONSTRAINT FK_CustomerLocks
        FOREIGN KEY (CustomerId, LockToken)
        REFERENCES CustomerLocks (CustomerId, LockToken)
GO



--Use a trigger to enforce the locks...
CREATE TRIGGER tg_EnforceCustomerLocks
ON Sales.Customer
FOR UPDATE
AS
BEGIN
    SET NOCOUNT ON

	--Force the caller to update the 
	--LockToken column
    IF EXISTS
        (
            SELECT *
            FROM inserted
            WHERE LockToken IS NULL
        )
    BEGIN
        RAISERROR('LockToken is a required column', 16, 1)
        ROLLBACK
		RETURN
    END

	--Reset the lock
    UPDATE Sales.Customer
    SET LockToken = NULL
    WHERE
        CustomerId IN
        (
            SELECT CustomerId
            FROM inserted
        )
END
GO



--This is ON by default in 2005
ALTER DATABASE AdventureWorks
SET RECURSIVE_TRIGGERS OFF
GO



--Try an update without sending the token
UPDATE Sales.Customer
SET CustomerType = CustomerType
WHERE CustomerId = 123
GO


--Try an update with an invalid token
UPDATE Sales.Customer
SET 
	CustomerType = CustomerType,
	LockToken = NEWID()
WHERE 
	CustomerId = 123
GO


--Get a lock and use it for an update...
DECLARE @CustomerId INT
SET @CustomerId = 123

DECLARE @LockToken UNIQUEIDENTIFIER

BEGIN TRY
    --Generate the token
    SET @LockToken = NEWID()

    INSERT CustomerLocks
    (
        CustomerId,
        LockToken
    )
    VALUES 
    (
        @CustomerId,
        @LockToken
    )
END TRY
BEGIN CATCH
    --Caught an exception: No lock acquired
    SET @LockToken = NULL
END CATCH

SELECT @LockToken AS Lock_Token
GO


--NULL to start
SELECT LockToken
FROM Sales.Customer
WHERE CustomerId = 123
GO

--Try an update with an invalid token
UPDATE Sales.Customer
SET 
	CustomerType = CustomerType,
	LockToken = '17707FA7-6B8A-4AB2-A5BA-ADF92B121E50' --insert token here
WHERE 
	CustomerId = 123
GO

--...NULL to finish
SELECT LockToken
FROM Sales.Customer
WHERE CustomerId = 123
GO


--Clean up
DROP TRIGGER Sales.tg_EnforceCustomerLocks
GO
ALTER TABLE Sales.Customer
DROP FK_CustomerLocks
GO
ALTER TABLE Sales.Customer
DROP COLUMN LockToken
GO
DROP TABLE CustomerLocks
GO