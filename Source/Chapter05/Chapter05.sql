--Create a database master key
CREATE MASTER KEY ENCRYPTION BY PASSWORD =
  'GiAFn1Blj2jxsUgmJm70c4Lb1dt4zLPD29GtrtJvEkBhLozTKrA4qAfOsIvS2EY'
GO



--Alter the master key
ALTER MASTER KEY DROP ENCRYPTION BY SERVICE MASTER KEY
GO


--Open the master key
OPEN MASTER KEY DECRYPTION BY PASSWORD = 
    'GiAFn1Blj2jxsUgmJm70c4Lb1dt4zLPD29GtrtJvEkBhLozTKrA4qAfOsIvS2EY'
GO


--HashBytes function
SELECT HashBytes('SHA1', 'ClearText')
GO



--Creating a certificate and an asymmetric key
CREATE CERTIFICATE MyCert
    WITH Subject = 'My Person Cert'
GO

CREATE ASYMMETRIC KEY AsymKeyPerson
    WITH Algorithm = RSA_1024
GO



--Grant permissions on the key
GRANT VIEW DEFINITION ON ASYMMETRIC KEY AsymKeyPerson TO Pam
GO

GRANT CONTROL ON ASYMMETRIC KEY AsymKeyPerson TO Tom
GO



--Insert data, encrypted with the key
INSERT INTO Person
(
    SocialSecurityNumber
)
SELECT 
    EncryptByAsymKey(AsymKey_ID('MyAsymKey'), SocialSecurityNumber)
FROM Source
GO



--Decrypt data with the key
SELECT 
    CONVERT(
        NVARCHAR(9),
        DecryptByAsymKey(
            AsymKey_ID('MyAsymKey'),
            SocialSecurityNumber))
FROM Person
GO


--Create a symmetric key
CREATE SYMMETRIC KEY MySymKey WITH ALGORITHM = AES_128
    ENCRYPTION BY CERTIFICATE MyCert
GO

GRANT CONTROL ON CERTIFICATE MyCert TO Jack
GO

GRANT VIEW DEFINITION ON SYMMETRIC KEY MySymKey TO Jack
GO



--Open the key, insert some data, then close it
OPEN SYMMETRIC KEY MySymKey
    DECRYPTION BY CERTIFICATE MyCert;
GO

INSERT INTO Person
(
    SocialSecurityNumber
)
SELECT 
    EncryptByKey(
        Key_GUID('MySymKey'), 
        SocialSecurityNumber)
FROM Source
GO

CLOSE SYMMETRIC KEY MySymKey;
GO



--Open the key and decrypt some data
OPEN SYMMETRIC KEY MySymKey
    DECRYPTION BY CERTIFICATE MyCert;
GO

SELECT 
    DecryptByKey(
        Key_GUID('MySymKey'), 
        SocialSecurityNumber)
FROM Person
GO

CLOSE SYMMETRIC KEY MySymKey;
GO


--Create a table and some keys
CREATE TABLE PersonID
(
    PersonID INT IDENTITY(1,1),
    SocialSecurityNumber VARBINARY(100)
)
GO

CREATE CERTIFICATE CertPerson
    ENCRYPTION BY PASSWORD = 'pJBp4bb92548d243Ll12'
    WITH Subject = 'Person Cert', 
    Expiry_Date = '01/01/2009'
GO

CREATE SYMMETRIC KEY SymKeyPerson_1 
    WITH ALGORITHM = TRIPLE_DES
    ENCRYPTION BY CERTIFICATE CertPerson
GO

CREATE SYMMETRIC KEY SymKeyPerson_2 
    WITH ALGORITHM = TRIPLE_DES
    ENCRYPTION BY CERTIFICATE CertPerson
GO



--Insert data
OPEN SYMMETRIC KEY SymKeyPerson_1
    DECRYPTION BY CERTIFICATE CertPerson
    WITH PASSWORD = 'pJBp4bb92548d243Ll12';
GO
INSERT INTO PersonID
SELECT 
    EncryptByKey(
        Key_GUID('SymKeyPerson_1'), 
        N'111111111')
GO
CLOSE SYMMETRIC KEY SymKeyPerson_1;
GO

OPEN SYMMETRIC KEY SymKeyPerson_2
    DECRYPTION BY CERTIFICATE CertPerson
    WITH PASSWORD = 'pJBp4bb92548d243Ll12';
GO

INSERT INTO PersonID
SELECT 
    EncryptByKey(
        Key_GUID('SymKeyPerson_2'), 
        N'222222222')
GO

CLOSE SYMMETRIC KEY SymKeyPerson_2;
GO


--Another way to decrypt
SELECT 
    PersonID,
    CONVERT(
        NVARCHAR(9), 
        DecryptByKeyAutoCert(
            Cert_ID('CertPerson'),
            N'pJBp4bb92548d243Ll12', 
            SocialSecurityNumber)
    ) AS SocialSecurityNumber
FROM PersonID;
GO


--Encapsulating decryption in a view
CREATE VIEW vw_Person 
AS
SELECT 
    CONVERT(
        NVARCHAR(9), 
        DecryptByKeyAutoCert (
            Cert_ID('CertPerson'),
            N'pJBp4bb92548d243Ll12', 
            SocialSecurityNumber)
    ) AS SocialSecurityNumber
FROM PersonID
GO



--Drop and re-create the table
IF  EXISTS 
    (
        SELECT * 
        FROM INFORMATION_SCHEMA.TABLES
        WHERE 
            TABLE_NAME = 'PersonID'
    )
    DROP TABLE PersonID
GO

CREATE TABLE PersonID
(
    PersonID INT IDENTITY(1,1), 
    SocialSecurityNumber VARBINARY(100), 
    BirthDate VARBINARY(100)
)
GO



--Create users and grant permissions
CREATE USER HR_User WITHOUT LOGIN
CREATE USER CustomerService WITHOUT LOGIN
GO

GRANT CONTROL ON CERTIFICATE::CertPerson TO CustomerService, HR_User
GRANT VIEW DEFINITION ON SYMMETRIC KEY::SymKeyPerson_1 TO HR_User
GRANT VIEW DEFINITION ON SYMMETRIC KEY::SymKeyPerson_2
    TO CustomerService, HR_User
GRANT SELECT ON PersonID TO CustomerService, HR_User
GO



--Insert encrypted data into the table
OPEN SYMMETRIC KEY SymKeyPerson_1
    DECRYPTION BY CERTIFICATE CertPerson
    WITH PASSWORD = 'pJBp4bb92548d243Ll12';
OPEN SYMMETRIC KEY SymKeyPerson_2
    DECRYPTION BY CERTIFICATE CertPerson
    WITH PASSWORD = 'pJBp4bb92548d243Ll12';
GO

INSERT INTO PersonID
SELECT 
    EncryptByKey(Key_GUID('SymKeyPerson_1'), N'111111111'),
    EncryptByKey(Key_GUID('SymKeyPerson_2'), N'02/02/1977')
GO

INSERT INTO PersonID
SELECT 
    EncryptByKey(Key_GUID('SymKeyPerson_1'), N'222222222'),
    EncryptByKey(Key_GUID('SymKeyPerson_2'), N'01/01/1967')
GO

CLOSE SYMMETRIC KEY SymKeyPerson_1;
CLOSE SYMMETRIC KEY SymKeyPerson_2;
GO



--Impersonate a user and try to get some data
EXECUTE AS USER = 'CustomerService'
GO

SELECT 
    PersonID, 
    CONVERT(
        NVARCHAR(9), 
        DecryptByKeyAutoCert (
            Cert_ID('CertPerson') ,
            N'pJBp4bb92548d243Ll12', 
            SocialSecurityNumber)
    ) AS SocialSecurityNumber,
    CONVERT(
        NVARCHAR(9), 
        DecryptByKeyAutoCert (
            Cert_ID('CertPerson') ,
            N'pJBp4bb92548d243Ll12', 
            BirthDate)
    ) AS BirthDate
FROM PersonID;
GO

REVERT
GO



--Passphrase decryption in a stored proc
CREATE PROCEDURE GetPersonData
    @PassphraseEnteredByUser VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON

    SELECT
        CONVERT(
            NVARCHAR(9), 
            DecryptByPassphrase(
                @PassphraseEnteredByUser, 
                SocialSecurityNumber)
        ) AS PersonData
    FROM PersonID
END
GO



--In SQL 2000, this would hide the batch from Profiler
EXEC GetPersonData N'Passphrase'  --sp_password
GO



--Decryption in a proc
CREATE PROCEDURE GET_Person
AS
    SET NOCOUNT ON

    SELECT 
        CONVERT(
            NVARCHAR(9), 
            DecryptByKey(SocialSecurityNumber)
        ) AS Person
    FROM Personid
GO



--Create a database with a table
IF  NOT EXISTS 
    (
        SELECT * 
        FROM sys.databases 
        WHERE name = N'Credit'
    )
    CREATE DATABASE Credit
GO

USE Credit
GO

IF  EXISTS 
    (
        SELECT * 
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_NAME = 'CreditCard' 
    )
    DROP TABLE CreditCard
GO

CREATE TABLE CreditCard 
(
    CreditCardId INT IDENTITY(1,1) NOT NULL,
    CreditCardNumber VARBINARY(100) NOT NULL,
    CONSTRAINT PK_CreditCard 
        PRIMARY KEY CLUSTERED(CreditCardId)
)
GO



--Create a user in the database, and grant showplan permissions
CREATE USER CreditCardUser WITHOUT LOGIN
GO

GRANT SELECT, UPDATE, INSERT ON CreditCard TO CreditCardUser
GO

GRANT SHOWPLAN TO CreditCardUser
GO


--Create keys and grant control
IF NOT EXISTS
    (
        SELECT * 
        FROM sys.Symmetric_Keys
        WHERE name LIKE '%DatabaseMasterKey%'
    )
CREATE MASTER KEY ENCRYPTION BY PASSWORD =
    'GiAFn1Blj2jxsUgmJm70c4Lb1dt4zLPD29GtrtJvEkBhLozTKrA4qAfOsIvS2EY'
GO

IF NOT EXISTS
    (
        SELECT * 
        FROM sys.Asymmetric_Keys
        WHERE name = 'CreditCardAsymKey'
    )
CREATE ASYMMETRIC KEY CreditCardAsymKey
    WITH Algorithm = RSA_1024
GO

GRANT CONTROL ON ASYMMETRIC KEY::CreditCardAsymKey TO CreditCardUser
GO



--Create a symmetric key
IF NOT EXISTS
    (
        SELECT * 
        FROM sys.Symmetric_Keys
        WHERE name = 'CreditCardSymKey'
    )
CREATE SYMMETRIC KEY CreditCardSymKey
    WITH ALGORITHM = TRIPLE_DES
    ENCRYPTION BY ASYMMETRIC KEY  CreditCardAsymKey
GO

GRANT VIEW DEFINITION ON SYMMETRIC KEY::CreditCardSymKey TO CreditCardUser
GO



--Impersonate and insert some data
EXECUTE AS USER = 'CreditCardUser'
GO

OPEN SYMMETRIC KEY CreditCardSymKey
    DECRYPTION BY ASYMMETRIC KEY CreditCardAsymKey;
GO

DECLARE @i bigint
SET @i = 19999999999000

WHILE @i <= 19999999999999
BEGIN
    INSERT INTO CreditCard
    (
        CreditCardNumber
    )
    SELECT 
        EncryptByKey(
            Key_GUID('CreditCardSymKey'), 
            CAST(@i AS NVARCHAR(14)))

    SET @i = @i + 1
END
GO

CLOSE SYMMETRIC KEY CreditCardSymKey;
GO

REVERT
GO



--Index the table
CREATE NONCLUSTERED INDEX IX_CreditCardNumber 
    ON CreditCard (CreditCardNumber)
GO



--Impersonate, and search the table
EXECUTE AS USER = 'CreditCardUser'
GO

DECLARE @SearchCritera NVARCHAR(14)
SET @SearchCritera = N'19999999999010'

SELECT
    CONVERT(
        NVARCHAR(50),
        DecryptByKeyAutoAsymKey(
            AsymKey_ID('CreditCardAsymKey'),  
            NULL ,
            CreditCardNumber))
FROM CreditCard
WHERE
    CONVERT(
        NVARCHAR(50),
        DecryptByKeyAutoAsymKey(
            AsymKey_ID('CreditCardAsymKey'),  
            NULL,
            CreditCardNumber)
    ) = @SearchCritera
GO
REVERT
GO



--Encrypt some data
SELECT EncryptByPassPhrase('Passphrase', 'EncryptMe')
GO



--Create a table for a MAC
IF  EXISTS 
    (
        SELECT * 
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_NAME = 'MacKey' 
    )
    DROP TABLE MacKey
GO

CREATE TABLE MacKey
(
    MacKeyID INT IDENTITY(1,1) NOT NULL,
    KeyData VARBINARY(256) NOT NULL,
    CONSTRAINT PK_MacKey 
        PRIMARY KEY CLUSTERED(MacKeyID)
)
GO



--Insert into the table
INSERT INTO MacKey
(
    KeyData
)
SELECT 
    EncryptByAsymKey(
        AsymKey_ID('CreditCardAsymKey'),
       'F65rjUcXAU57YSfJf32ddWdTzlAdRMW8Ph'))
GO



--The BuildMac function
CREATE FUNCTION BuildMac
(
    @PlainTextData NVARCHAR(MAX)
)
RETURNS VARBINARY(24)
AS
BEGIN
    DECLARE @return VARBINARY(24)
    DECLARE @macKey NVARCHAR(100)

    SET @return = NULL
    SET @macKey = NULL

    SET @macKey = (
        SELECT 
            CONVERT(
                NVARCHAR(36),
                DecryptByAsymKey(
                    AsymKey_ID('CreditCardAsymKey'), 
                    KeyData))
        FROM MacKey)

    IF(@macKey IS NOT NULL)
        SET @return = (
            SELECT 
                HashBytes(
                    'SHA1', 
                    UPPER(@PlainTextData) + @macKey))

    RETURN @return
END
GO

GRANT EXECUTE ON BuildMac TO CreditCardUser
GO



--Put the MAC on the CreditCard table
IF  EXISTS 
    (
        SELECT * 
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_NAME = 'CreditCard' 
    )
    DROP TABLE CreditCard
GO

CREATE TABLE CreditCard 
(
    CreditCardId INT IDENTITY(1,1) NOT NULL,
    CreditCardNumber NVARCHAR(100) NOT NULL,
    CreditCardNumberMac VARBINARY(50) NOT NULL,
    CONSTRAINT PK_CreditCard 
        PRIMARY KEY CLUSTERED(CreditCardId)
)
GO

GRANT SELECT, UPDATE, INSERT ON CreditCard TO CreditCardUser
GO



--Trigger to maintain the MAC
CREATE TRIGGER ins_CreditCard 
ON CreditCard
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON

    IF EXISTS
        (  
            SELECT * 
            FROM inserted 
            WHERE CreditCardNumber IS NULL 
        )
        RAISERROR( 'Credit Card Number is required', 16, 1)
    ELSE
    BEGIN
        INSERT INTO CreditCard
        (
            CreditCardNumber,
            CreditCardNumberMac
        )
        SELECT
            EncryptByKey(
                Key_GUID('CreditCardSymKey'), 
                CreditCardNumber),
            BuildMac(CreditCardNumber)
        FROM inserted
    END
END
GO



--Populate the table...
EXECUTE AS USER = 'CreditCardUser'
GO

OPEN SYMMETRIC KEY CreditCardSymKey
DECRYPTION BY ASYMMETRIC KEY CreditCardAsymKey
GO

DECLARE @i BIGINT
SET @i = 19999999999000

WHILE @i <= 19999999999999
BEGIN
    INSERT INTO CreditCard
    (
        CreditCardNumber
    )
    SELECT @i

    SET @i = @i + 1
END
GO

CLOSE SYMMETRIC KEY CreditCardSymKey
GO

REVERT
GO



--Trigger to handle inserts
CREATE TRIGGER upd_CreditCard 
ON CreditCard
    INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON

    IF (UPDATE(CreditCardNumberMAC))
        RAISERROR( 'Update not allowed.', 16, 1 )
    ELSE
    BEGIN
        UPDATE cc
        SET 
            CreditCardNumberMac = BuildMac(i.CreditCardNumber),
            CreditCardNumber =  
                EncryptByKey(
                    Key_GUID('CreditCardSymKey'),
                    i.CreditCardNumber)
        FROM inserted i 
        INNER JOIN CreditCard cc ON i.CreditCardId = cc.CreditCardId
    END
END
GO



--Index the MAC
CREATE NONCLUSTERED INDEX IX_CreditCardNumberMac 
    ON CreditCard (CreditCardNumberMac ASC)
    INCLUDE (CreditCardNumber)
GO



--Impersonate, and update the table
EXECUTE AS USER = 'CreditCardUser'
GO

OPEN SYMMETRIC KEY CreditCardSymKey
    DECRYPTION BY ASYMMETRIC KEY CreditCardAsymKey
GO

UPDATE CreditCard
SET CreditCardNumber = '12345678910000'
WHERE 
    BuildMac('19999999999000') = CreditCardNumberMac
    AND CONVERT(
        NVARCHAR(14), 
        DecryptByKeyAutoAsymKey(
            AsymKey_ID('CreditCardAsymKey'),  
            NULL,
            CreditCardNumber)
    )= N'19999999999000'
GO

CLOSE SYMMETRIC KEY CreditCardSymKey
GO

REVERT
GO



--Impersonate, and get some data
EXECUTE AS USER = 'CreditCardUser'
GO

SELECT   
    CONVERT(
        NVARCHAR(50),
        DecryptByKeyAutoAsymKey(
            AsymKey_ID('CreditCardAsymKey'),  
            NULL,
            CreditCardNumber)
    ) AS CreditCardNumber
FROM CreditCard
WHERE BuildMac('12345678910000') = CreditCardNumberMac
GO

REVERT
GO



--Impersonate, and do a search without the MAC
EXECUTE AS USER = 'CreditCardUser'
GO

DECLARE @SearchCritera NVARCHAR(14)
SET @SearchCritera = N'19999999999010'

SELECT
    CONVERT(
        NVARCHAR(50),
        DecryptByKeyAutoAsymKey(
            AsymKey_ID('CreditCardAsymKey'),  
            NULL,
            CreditCardNumber))
FROM CreditCard
WHERE
    CONVERT(
        NVARCHAR(50),
        DecryptByKeyAutoAsymKey(
            AsymKey_ID('CreditCardAsymKey'),  
            NULL,
            CreditCardNumber)
    ) = @SearchCritera
GO

REVERT
GO



--Impersonate, and do a search with the MAC
EXECUTE AS USER = 'CreditCardUser'
GO

DECLARE @SearchCritera NVARCHAR(14)
SET @SearchCritera = N'19999999999010'

SELECT
    CONVERT(
        NVARCHAR(50),
            DecryptByKeyAutoAsymKey(
                AsymKey_ID('CreditCardAsymKey'),  
                NULL,
                CreditCardNumber))
FROM CreditCard
WHERE 
    CreditCardNumberMac = BuildMac(@SearchCritera)
    AND CONVERT(
        NVARCHAR(14), 
        DecryptByKeyAutoAsymKey(
            AsymKey_ID('CreditCardAsymKey'),  
            NULL,
            CreditCardNumber)
    )= @SearchCritera
GO

REVERT
GO



--Add a column for substring MAC searching
IF  EXISTS 
    (
        SELECT * 
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_NAME = 'CreditCard' 
    )
DROP TABLE CreditCard
GO

CREATE TABLE CreditCard 
(
    CreditCardId INT IDENTITY(1,1) NOT NULL,
    CreditCardNumber NVARCHAR(100) NOT NULL,
    CreditCardNumberMac VARBINARY(50) NOT NULL,
    CreditCardNumberSubstringMac VARBINARY(50) NOT NULL,
    CONSTRAINT PK_CreditCard 
        PRIMARY KEY CLUSTERED(CreditCardId)
)
GO

GRANT SELECT, UPDATE, INSERT ON CreditCard TO CreditCardUser
GO

CREATE NONCLUSTERED INDEX IX_CreditCardNumberSubstringMac 
    ON CreditCard (CreditCardNumberSubstringMac)
    INCLUDE (CreditCardNumber)
GO



--Re-create the triggers
CREATE TRIGGER ins_CreditCard 
    ON CreditCard
    INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON

    IF EXISTS
        (
            SELECT * 
            FROM inserted 
            WHERE CreditCardNumber IS NULL 
        )
        RAISERROR( 'Credit Card Number is required', 16, 1)
    ELSE
    BEGIN
        INSERT INTO CreditCard
        (
            CreditCardNumber, 
            CreditCardNumberMac,
            CreditCardNumberSubstringMac
        )
        SELECT
            EncryptByKey(
                Key_GUID('CreditCardSymKey'), 
                CreditCardNumber),
            BuildMac(CreditCardNumber),
            BuildMac(RIGHT(CreditCardNumber, 4))
        FROM inserted
    END
END
GO

CREATE TRIGGER upd_CreditCard 
    ON CreditCard
    INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON

    IF 
        (
            UPDATE(CreditCardNumberMAC) 
            OR UPDATE(CreditCardNumberSubstringMac)
        )
        RAISERROR( 'Update not allowed.', 16, 1 )
    ELSE
    BEGIN
        UPDATE cc
        SET
            CreditCardNumberMac = BuildMac(i.CreditCardNumber),
            CreditCardNumberSubstringMac =
                BuildMac(RIGHT(i.CreditCardNumber, 4)),
            CreditCardNumber =
                EncryptByKey(
                    Key_GUID('CreditCardSymKey'), 
                    i.CreditCardNumber)
        FROM inserted i 
        INNER JOIN CreditCard cc ON i.CreditCardId = cc.CreditCardId
    END
END
GO




--Populate some data
EXECUTE AS USER = 'CreditCardUser'
GO

OPEN SYMMETRIC KEY CreditCardSymKey
    DECRYPTION BY ASYMMETRIC KEY CreditCardAsymKey
GO

DECLARE @i BIGINT
SET @i = 19999999999000

WHILE @i <= 19999999999999
BEGIN
    INSERT INTO CreditCard
    (
        CreditCardNumber
    )
    SELECT @i

    SET @i = @i + 1
END
GO

CLOSE SYMMETRIC KEY CreditCardSymKey
GO

REVERT
GO




--Substring search
EXECUTE AS USER = 'CreditCardUser'
GO

DECLARE @SearchCritera NVARCHAR(14)
SET @SearchCritera = N'9999456'

SELECT
    CONVERT(
        NVARCHAR(14),
        DecryptByKeyAutoAsymKey(
            AsymKey_ID('CreditCardAsymKey'), 
            NULL,
            CreditCardNumber)) 
FROM CreditCard
WHERE 
    CreditCardNumberSubstringMac = BuildMac(RIGHT(@SearchCritera, 4))
    AND CONVERT(
        NVARCHAR(14),
        DecryptByKeyAutoAsymKey(
            AsymKey_ID('CreditCardAsymKey'), 
            NULL, 
            CreditCardNumber)
        ) LIKE '%' + @SearchCritera
GO

REVERT
GO




