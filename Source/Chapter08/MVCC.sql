USE TempDB
GO

--Create a table to test updates...
CREATE TABLE Test_Updates
(
    PK_Col INT NOT NULL PRIMARY KEY,
    Other_Col VARCHAR(100) NOT NULL
)
GO

INSERT Test_Updates
(
    PK_Col,
    Other_Col
)
SELECT
    EmployeeId,
    Title
FROM AdventureWorks.HumanResources.Employee
GO


CREATE TABLE Test_Inserts
(
    PK_Col INT NOT NULL,
    Other_Col VARCHAR(100) NOT NULL,
    Version INT IDENTITY(1,1) NOT NULL,
    PRIMARY KEY (PK_Col, Version)
)
GO



--Get the latest version of each row
SELECT
    ti.PK_Col,
    ti.Other_Col,
    ti.Version
FROM Test_Inserts ti
WHERE
    Version = 
    (
        SELECT MAX(ti1.Version)
        FROM Test_Inserts ti1
        WHERE 
            ti1.PK_Col = ti.PK_Col
    )
GO



--Get a snapshot as of a given version
SELECT
    ti.PK_Col,
    ti.Other_Col,
    ti.Version
FROM Test_Inserts ti
WHERE
    Version = 
    (
        SELECT MAX(ti1.Version)
        FROM Test_Inserts ti1
        WHERE 
            ti1.PK_Col = ti.PK_Col
			--Pass in the version you want
			--a snapshot at
			AND Version <= 200
    )
GO



--Clean up
DROP TABLE Test_Updates
GO
DROP TABLE Test_Inserts
GO