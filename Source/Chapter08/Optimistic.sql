USE AdventureWorks
GO


--Try #1: ROWVERSION columns
CREATE TABLE CustomerNames
(
    CustomerId INT NOT NULL PRIMARY KEY,
    CustomerName VARCHAR(50) NOT NULL,
    Version ROWVERSION NOT NULL
)
GO



--Insert some rows
INSERT CustomerNames
(	
    CustomerId,
    CustomerName
)
SELECT 123, 'Ron Talmage'
UNION ALL
SELECT 456, 'Andrew Kelly'
GO



--Check out the data
SELECT *
FROM CustomerNames
GO


--Update...
UPDATE CustomerNames
SET CustomerName = 'Kalen Delaney'
WHERE CustomerId = 456
GO



--The ROWVERSION for 456 has changed
--Always send the version back to the caller
SELECT *
FROM CustomerNames
GO



--An optimistic way to handle optimism
DECLARE @CustomerName VARCHAR(50)
SET @CustomerName = 'Kimberly Tripp'

DECLARE @CustomerId INT
SET @CustomerId = 456

UPDATE CustomerNames
SET CustomerName = @CustomerName
WHERE
    CustomerId = @CustomerId
    AND Version = 0x0000000000062255--Insert version here...

IF @@ROWCOUNT = 0
    RAISERROR('Version conflict encountered', 16, 1)
GO




--Problem #1:
--What if not everyone follows the rules?
--Fix: Yet another trigger!
DROP TABLE CustomerNames
GO

--Use a UNIQUEIDENTIFIER or DATETIME
--instead of ROWVERSION
CREATE TABLE CustomerNames
(
    CustomerId INT NOT NULL PRIMARY KEY,
    CustomerName VARCHAR(50) NOT NULL,
    Version UNIQUEIDENTIFIER NOT NULL
        DEFAULT (NEWID())
)
GO


CREATE TRIGGER tg_UpdateCustomerNames
ON CustomerNames
FOR UPDATE AS
BEGIN
    SET NOCOUNT ON

	--Force the caller to update the Version column
	--treat the version as a lock token!
    IF NOT UPDATE(Version)
    BEGIN
        RAISERROR('Updating the Version column is required', 16, 1)
        ROLLBACK
    END

	--Are the versions the same?
    IF EXISTS
        (
            SELECT *
            FROM inserted i
            JOIN deleted d ON i.CustomerId = d.CustomerId
            WHERE i.Version <> d.Version        
        )
    BEGIN
        RAISERROR('Version conflict encountered', 16, 1)
        ROLLBACK
    END
    ELSE
        --Set new versions for the updated rows
        UPDATE CustomerNames
        SET Version = NEWID()
        WHERE 
            CustomerId IN
            (
                SELECT CustomerId
                FROM inserted
            )
END
GO


--Insert some rows
INSERT CustomerNames
(	
    CustomerId,
    CustomerName
)
SELECT 123, 'Ron Talmage'
UNION ALL
SELECT 456, 'Andrew Kelly'
GO


SELECT * 
FROM CustomerNames
GO



--Now the optimism is enforced...
DECLARE @CustomerName VARCHAR(50)
SET @CustomerName = 'Kimberly Tripp'

DECLARE @CustomerId INT
SET @CustomerId = 456

UPDATE CustomerNames
SET CustomerName = @CustomerName
WHERE
    CustomerId = @CustomerId
GO



--Invalid token?
DECLARE @CustomerName VARCHAR(50)
SET @CustomerName = 'Kimberly Tripp'

DECLARE @CustomerId INT
SET @CustomerId = 456

UPDATE CustomerNames
SET
	CustomerName = @CustomerName,
	Version = NEWID()
WHERE
    CustomerId = @CustomerId
GO


--Use the correct token
SELECT *
FROM CustomerNames
GO

DECLARE @CustomerName VARCHAR(50)
SET @CustomerName = 'Kimberly Tripp'

DECLARE @CustomerId INT
SET @CustomerId = 456

UPDATE CustomerNames
SET 
	CustomerName = @CustomerName,
	Version = '2077FE70-0432-44A3-81BE-481D3C460928' --Insert correct token here
WHERE
    CustomerId = @CustomerId
GO



--Problem 2:
--User experience isn't great when
--a conflict occurs.
--Fix: Send back some data...
ALTER TRIGGER tg_UpdateCustomerNames
ON CustomerNames
FOR UPDATE AS
BEGIN
    SET NOCOUNT ON

	--Force the caller to update the Version column
	--treat the version as a lock token!
    IF NOT UPDATE(Version)
    BEGIN
        RAISERROR('Updating the Version column is required', 16, 1)
        ROLLBACK
    END

	--Are the versions the same?
    IF EXISTS
        (
            SELECT *
            FROM inserted i
            JOIN deleted d ON i.CustomerId = d.CustomerId
            WHERE i.Version <> d.Version        
        )
    BEGIN
		--Fake an XML DiffGram
		SELECT
			(
				SELECT 
					ROW_NUMBER() OVER (ORDER BY CustomerId) AS [@row_number],
					*
				FROM inserted
				FOR XML PATH('customer_name'), TYPE
			) new_values,
			(
				SELECT 
					ROW_NUMBER() OVER (ORDER BY CustomerId) AS [@row_number],
					*
				FROM deleted
				FOR XML PATH('customer_name'), TYPE
			) old_values
		FOR XML PATH('customer_name_rows')

        RAISERROR('Version conflict encountered', 16, 1)
        ROLLBACK
    END
    ELSE
        --Set new versions for the updated rows
        UPDATE CustomerNames
        SET Version = NEWID()
        WHERE 
            CustomerId IN
            (
                SELECT CustomerId
                FROM inserted
            )
END
GO



DECLARE @CustomerName VARCHAR(50)
SET @CustomerName = 'Bob Beauchemin'

DECLARE @CustomerId INT
SET @CustomerId = 456

UPDATE CustomerNames
SET 
	CustomerName = @CustomerName,
	Version = '2077FE70-0432-44A3-81BE-481D3C460928' --Insert correct token here
WHERE
    CustomerId = @CustomerId
GO



--Clean up
DROP TABLE CustomerNames
GO