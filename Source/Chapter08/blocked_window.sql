USE TempDB
GO


--01: Try to select from the table
SELECT *
FROM Blocker
GO



--02: Try an update
BEGIN TRANSACTION

UPDATE Blocker
SET Blocker_Id = Blocker_Id + 1
GO



ROLLBACK
GO



--03: Blocked update
BEGIN TRANSACTION

UPDATE Blocker
SET Blocker_Id = Blocker_Id + 1
GO



ROLLBACK
GO



--03: Non-blocked insert
BEGIN TRANSACTION

INSERT Blocker
SELECT 4

COMMIT
GO



--04: Blocked update
BEGIN TRANSACTION

UPDATE Blocker
SET Blocker_Id = Blocker_Id + 1
GO



ROLLBACK
GO



--05: Non-blocked (dirty) read
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

SELECT *
FROM Blocker
GO



