USE TempDB
GO

--Create the Blocker table
CREATE TABLE Blocker
(
    Blocker_Id INT NOT NULL
        PRIMARY KEY
)
GO

INSERT Blocker
SELECT 1
UNION ALL
SELECT 2
UNION ALL
SELECT 3
GO



--01: Test blocking update
BEGIN TRANSACTION

UPDATE Blocker
SET Blocker_Id = Blocker_Id + 1
GO



ROLLBACK
GO



--02: Test blocking read
BEGIN TRANSACTION

SELECT *
FROM Blocker
GO



ROLLBACK
GO



--03: REPEATABLE READ
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ

BEGIN TRANSACTION

SELECT *
FROM Blocker
GO



ROLLBACK
GO



--04: SERIALIZABLE
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE

BEGIN TRANSACTION

SELECT *
FROM Blocker
WHERE Blocker_Id
GO



ROLLBACK
GO



--05: Update...
BEGIN TRANSACTION

UPDATE Blocker
SET Blocker_Id = 10
WHERE Blocker_Id = 1
GO



ROLLBACK
GO



