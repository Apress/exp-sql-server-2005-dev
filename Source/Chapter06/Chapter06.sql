
--Create a certificate and a proxy login
USE master
GO

CREATE CERTIFICATE Assembly_Permissions_Certificate
ENCRYPTION BY PASSWORD = 'uSe_a STr()nG PaSSW0rD!'
WITH SUBJECT = 'Certificate used to grant assembly permission'
GO

CREATE LOGIN Assembly_Permissions_Login
FROM CERTIFICATE Assembly_Permissions_Certificate
GO

--Grant the assembly permission
GRANT UNSAFE ASSEMBLY TO Assembly_Permissions_Login
GO



--Backup the certificate
BACKUP CERTIFICATE Assembly_Permissions_Certificate
TO FILE = 'C:\assembly_permissions.cer'
WITH PRIVATE KEY
(
    FILE = 'C:\assembly_permissions.pvk',
    ENCRYPTION BY PASSWORD = 'is?tHiS_a_VeRySTronGP4ssWoR|)?',
    DECRYPTION BY PASSWORD = 'uSe_a STr()nG PaSSW0rD!'
)
GO


--Restore the certificate in a database, create a proxy user
USE AdventureWorks
GO

CREATE CERTIFICATE Assembly_Permissions_Certificate
FROM FILE = 'C:\assembly_permissions.cer'
WITH PRIVATE KEY
(
    FILE = 'C:\assembly_permissions.pvk',
    DECRYPTION BY PASSWORD = 'is?tHiS_a_VeRySTronGP4ssWoR|)?',
    ENCRYPTION BY PASSWORD = 'uSe_a STr()nG PaSSW0rD!'
)
GO

CREATE USER Assembly_Permissions_User
FOR CERTIFICATE Assembly_Permissions_Certificate
GO


--Sign the assembly
ADD SIGNATURE TO ASSEMBLY::SafeDictionary
BY CERTIFICATE Assembly_Permissions_Certificate
WITH PASSWORD='uSe_a STr()nG PaSSW0rD!'
GO



--Get Employee data in XML format
SELECT *
FROM HumanResources.Employee
FOR XML RAW, ROOT('Employees')
GO


--Serialize as XML, then deserialize
DECLARE @p XML
SET @p = 
(
	SELECT *
	FROM HumanResources.Employee
	FOR XML RAW, ROOT('Employees'), TYPE
)

SELECT
   col.value('@EmployeeID', 'int') AS EmployeeID,
   col.value('@NationalIDNumber', 'nvarchar(15)') AS NationalIDNumber,
   col.value('@ContactID', 'int') AS ContactID,
   col.value('@LoginID', 'nvarchar(256)') AS LoginID,
   col.value('@ManagerID', 'int') AS ManagerID,
   col.value('@Title', 'nvarchar(50)') AS Title,
   col.value('@BirthDate', 'datetime') AS BirthDate,
   col.value('@MaritalStatus', 'nchar(1)') AS MaritalStatus,
   col.value('@Gender', 'nchar(1)') AS Gender,
   col.value('@HireDate', 'datetime') AS HireDate,
   col.value('@SalariedFlag', 'bit') AS SalariedFlag,
   col.value('@VacationHours', 'smallint') AS VacationHours,
   col.value('@SickLeaveHours', 'smallint') AS SickLeaveHours,
   col.value('@CurrentFlag', 'bit') AS CurrentFlag,
   col.value('@rowguid', 'uniqueidentifier') AS rowguid,
   col.value('@ModifiedDate', 'datetime') AS ModifiedDate
FROM @p.nodes ('/Employees/row') p (col)
GO



--Use the GetDataTable_Binary function
DECLARE @sql NVARCHAR(4000)
SET @sql = 'SELECT * FROM HumanResources.Employee'

DECLARE @p VARBINARY(MAX)
SET @p =
    dbo.GetDataTable_Binary(@sql)
GO



--Use the GetBinaryFromQueryResult function
DECLARE @sql NVARCHAR(4000)
SET @sql = 'SELECT * FROM HumanResources.Employee'

DECLARE @p VARBINARY(MAX)
SET @p =
    dbo.GetBinaryFromQueryResult(@sql)
GO



--Serialize to binary, then deserialize
DECLARE @sql NVARCHAR(4000)
SET @sql = 'SELECT * FROM HumanResources.Employee'

DECLARE @p VARBINARY(MAX)
SET @p =
    dbo.GetBinaryFromQueryResult(@sql)

EXEC GetTableFromBinary @p
GO



--Using the string_concat UDA
SELECT dbo.String_Concat(Name)
FROM Production.Product
GO


--Using the string_concat_2 UDA
SELECT dbo.String_Concat_2(Name)
FROM Production.Product
GO

