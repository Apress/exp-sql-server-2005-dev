USE Spatial;
GO

-- Take a peek at the contents of the Place table.
SELECT
    PlaceName,
    State,
    Lat,
    Lon
FROM Place;
GO

-- Create the T-SQL function to calculate distance between two points.
CREATE FUNCTION Distance
(
    @Lat1 FLOAT,
    @Lon1 FLOAT,
    @Lat2 FLOAT,
    @Lon2 FLOAT,
    @Unit CHAR(2) = 'km'
)
RETURNS FLOAT
AS
BEGIN;
    DECLARE
        @Lat1R FLOAT,
        @Lon1R FLOAT,
        @Lat2R FLOAT,
        @Lon2R FLOAT,
        @DistR FLOAT,
        @Dist  FLOAT;

    -- Convert from degrees to radians
    SET @Lat1R = RADIANS(@Lat1);
    SET @Lon1R = RADIANS(@Lon1);
    SET @Lat2R = RADIANS(@Lat2);
    SET @Lon2R = RADIANS(@Lon2);

    -- Calculate the distance (in radians)
    SET @DistR =
        2 * ASIN(SQRT(
               POWER(SIN((@Lat1R - @Lat2R) / 2), 2) +
               (COS(@Lat1R) * COS(@Lat2R) * POWER(SIN((@Lon1R - @Lon2R) / 2), 2))));

    -- Convert distance from radians to kilometers or miles
    -- Convert distance from km/mi to radians
    -- Note: DistR = Distance in nautical miles * (pi / (180 * 60))
    --               One nautical mile is 1.852 kilometers, thus:
    --       DistR =(DistKM / 1.852) * pi / (180 * 60)
    --   or: DistR = DistKM * pi / (180 * 60 * 1.852)
    IF @Unit = 'km'
        SET @Dist = @DistR * 20001.6 / PI();
    ELSE
        SET @Dist = @DistR * 20001.6 / PI() / 1.609344;

    RETURN @Dist;
END;
GO

-- Calculate the distance between Seattle and Redmond, using T-SQL distance function.
WITH Seattle AS
(
    SELECT Lat, Lon
    FROM Place
    WHERE
        PlaceName = 'Seattle'
        AND State = 'WA'
)
,Redmond AS
(
    SELECT Lat, Lon
    FROM Place
    WHERE
        PlaceName = 'Redmond'
        AND State = 'WA'
)
SELECT
    dbo.Distance(s.Lat, s.Lon, r.Lat, r.Lon, 'km') AS DistInKilometers,
    dbo.Distance(s.Lat, s.Lon, r.Lat, r.Lon, 'mi') AS DistInMiles
FROM Seattle AS s
CROSS JOIN Redmond AS r;
GO

-- Compare correct distance algorithm to algorith based on the Pythagorean theorem.
DECLARE @State CHAR(2);
SET @State = 'FL';

WITH TwoCalculations
AS
(
    SELECT
        dbo.Distance(a.Lat, a.Lon, b.Lat, b.Lon, 'km') AS Correct,
        SQRT (POWER(a.Lat - b.Lat, 2)
             + POWER(a.Lon - b.Lon, 2)) * 111.12 AS Approx
    FROM Place AS a
    INNER JOIN Place AS b ON b.HtmID >= a.HtmID 
    WHERE
        a.State = @State
        AND b.State = @State
)
SELECT
    Correct,
    Approx,
    Approx - Correct AS Diff,
    (Approx - Correct) * 100.0 / NULLIF(Correct, 0.0) AS Perc
FROM TwoCalculations
ORDER BY Perc DESC;
GO

-- Create procedure to find new location based on starting location and distance + direction to move.
CREATE PROCEDURE Move
    @Lat1 FLOAT,
    @Lon1 FLOAT,
    @Dist FLOAT,
    @Dir  FLOAT,
    @Lat2 FLOAT OUTPUT,
    @Lon2 FLOAT OUTPUT,
    @Unit CHAR(2) = 'km'
AS
BEGIN;
    DECLARE
        @Lat1R FLOAT,
        @Lon1R FLOAT,
        @Lat2R FLOAT,
        @Lon2R FLOAT,
        @DLonR FLOAT,
        @DistR FLOAT,
        @DirR  FLOAT;

    -- Convert from degrees to radians
    SET @Lat1R = RADIANS(@Lat1);
    SET @Lon1R = RADIANS(@Lon1);
    SET @DirR  = RADIANS(@Dir);

    -- Convert distance from km/mi to radians
    -- Note: DistR = Distance in nautical miles * (pi / (180 * 60))
    --               One nautical mile is 1.852 kilometers, thus:
    --   or: DistR =(DistKM / 1.852) * pi / (180 * 60)
    --   or: DistR = DistKM * pi / (180 * 60 * 1.852)
    --   or: DistR = DistKM * pi / 20001.6
    -- Since one mile is 1.609344 kilometers, the formula for miles is:
    --       DistR =(DistMI * 1.609344) * pi / 20001.6
    --   or: DistR = DistMI * pi / (20001.6 / 1.609344)
    --   or: DistR = DistMI * pi / 12428.418038654259126700071581961
    IF @Unit = 'km'
        SET @DistR = @Dist * PI() / 20001.6;
    ELSE
        SET @DistR = @Dist * PI() / 12428.418038654259126700071581961;

    -- Calculate latitude of new point
    SET @Lat2R = ASIN(SIN(@Lat1R) * COS(@DistR)
                     + COS(@Lat1R) * SIN(@DistR) * COS(@DirR));

    -- Calculate longitude difference.
    SET @DLonR = ATN2(SIN(@DirR)  * SIN(@DistR) * COS(@Lat1R),
                      COS(@DistR) - SIN(@Lat1R) * SIN(@Lat2R));
    -- Calculate longitude of new point - ensure result is between -PI and PI.
    SET @Lon2R = (CAST(@Lon1R - @DLonR + PI() AS DECIMAL(38,37))
                 % CAST(2*PI() AS DECIMAL(38,37)))
                 - PI();

    -- Convert back to degrees
    SET @Lat2 = DEGREES(@Lat2R);
    SET @Lon2 = DEGREES(@Lon2R);
END;
GO

-- Test stored procedure Move by moving 100 kilometers northeast from Seattle.
DECLARE
    @Lat1 FLOAT,
    @Lon1 FLOAT,
    @Lat2 FLOAT,
    @Lon2 FLOAT;

SELECT
    @Lat1 = Lat,
    @Lon1 = Lon
FROM Place
WHERE
    PlaceName = 'Seattle'
    AND State = 'WA';

EXEC Move
    @Lat1,
    @Lon1,
    100,           -- Distance
    -45,           -- Direction
    @Lat2 OUTPUT,
    @Lon2 OUTPUT,
    'km';

SELECT
    @Lat2 AS Lat,
    @Lon2 AS Lon;
GO

-- Find places in a 10 kilometer radius by using the T-SQL distance calculation.
DECLARE
    @Lat FLOAT,
    @Lon FLOAT,
    @MaxDist FLOAT;

SET @Lat = 47.622;
SET @Lon = -122.35;
SET @MaxDist = 10.0;

WITH PlacePlusDistance
AS
(
    SELECT
        PlaceName,
        State,
        dbo.Distance (Lat, Lon, @Lat, @Lon, 'km') AS Dist
    FROM Place
)
SELECT
    PlaceName,
    State,
    CAST(Dist AS decimal(6,4)) AS Distance
FROM PlacePlusDistance
WHERE Dist < @MaxDist
ORDER BY Dist ASC;
GO

-- Find places in a 10 kilometer radius by copying the distance calculation inline.
DECLARE
    @Lat FLOAT,
    @Lon FLOAT,
    @MaxDist FLOAT;

SET @Lat = 47.622;
SET @Lon = -122.35;
SET @MaxDist = 10.0;

WITH PlacePlusDistance
AS
(
    SELECT
        PlaceName,
        State,
        2 * ASIN(SQRT(POWER(SIN((RADIANS(Lat) - RADIANS(@Lat)) / 2), 2)
                   + (COS(RADIANS(Lat)) * COS(RADIANS(@Lat))
                     * POWER(SIN((RADIANS(Lon) - RADIANS(@Lon)) / 2), 2)
                     ))) * 20001.6 / PI() AS Dist
    FROM Place
)
SELECT
    PlaceName,
    State,
    CAST(Dist AS decimal(6,4)) AS Distance
FROM PlacePlusDistance
WHERE Dist < @MaxDist
ORDER BY Dist ASC;
GO

-- Find places in a 10 kilometer radius by using the CLR distance calculation.
DECLARE
    @Lat FLOAT,
    @Lon FLOAT,
    @MaxDist FLOAT;
SET @Lat = 47.622;
SET @Lon = -122.35;
SET @MaxDist = 10.0;

WITH PlacePlusDistance
AS
(
    SELECT
        PlaceName,
        State,
        dbo.DistCLR (Lat, Lon, @Lat, @Lon, 'km') AS Dist
    FROM Place
)
SELECT
    PlaceName,
    State,
    CAST(Dist AS decimal(6,4)) AS Distance
FROM PlacePlusDistance
WHERE Dist < @MaxDist
ORDER BY Dist ASC;
GO

-- Find places in a 10 kilometer radius by using the T-SQL version of the bounding box.
DECLARE
    @Lat FLOAT,
    @Lon FLOAT,
    @MaxDist FLOAT;

SET @Lat = 47.622;
SET @Lon = -122.35;
SET @MaxDist = 10.0;

DECLARE
    @LatMin FLOAT,
    @LatMax FLOAT,
    @LonMin FLOAT,
    @LonMax FLOAT,
    @Dummy  FLOAT;

-- Determine minimum and maximum latitude and longitude
EXEC Move
    @Lat,
    @Lon,
    @MaxDist,
    0,                -- North
    @LatMax OUTPUT,
    @Dummy  OUTPUT,   -- Don't need this
    'km';

EXEC Move
    @Lat,
    @Lon,
    @MaxDist,
    90,               -- West
    @Dummy  OUTPUT,   -- Don't need this
    @LonMin OUTPUT,
    'km';

EXEC Move
    @Lat,
    @Lon,
    @MaxDist,
    180,              -- South
    @LatMin OUTPUT,
    @Dummy  OUTPUT,   -- Don't need this
    'km';

EXEC Move
    @Lat,
    @Lon,
    @MaxDist,
    -90,              -- East
    @Dummy  OUTPUT,   -- Don't need this
    @LonMax OUTPUT,
    'km';

WITH PlacePlusDistance
AS
(
    SELECT
        PlaceName,
        State,
        dbo.DistCLR (Lat, Lon, @Lat, @Lon, 'km') AS Dist
    FROM Place
    WHERE
        Lat BETWEEN @LatMin AND @LatMax
        AND Lon BETWEEN @LonMin AND @LonMax
)
SELECT
    PlaceName,
    State,
    CAST(Dist AS decimal(6,4)) AS Distance
FROM PlacePlusDistance
WHERE Dist < @MaxDist
ORDER BY Dist ASC;
GO

-- Adding an index to speed up the dynamic bounding box.
CREATE INDEX ix_LonLat ON Place(Lon,Lat)
INCLUDE(State, PlaceName);
GO

-- Create the T-SQL function for the bounding box.
CREATE FUNCTION dbo.GetNeighbors
(
    @Lat FLOAT,
    @Lon FLOAT,
    @MaxDist FLOAT,
    @Unit CHAR(2) = 'km'
)
RETURNS @Neighbors TABLE
(
    PlaceName VARCHAR(100) NOT NULL,
    State CHAR(2) NOT NULL,
    Dist FLOAT NOT NULL
)
AS
BEGIN
    DECLARE
        @LatMin FLOAT,
        @LatMax FLOAT,
        @LonMin FLOAT,
        @LonMax FLOAT,
        @Lat1R FLOAT,
        @Lon1R FLOAT,
        @Lat2R FLOAT,
        @Lon2R FLOAT,
        @DLonR FLOAT,
        @MaxDistR FLOAT,
        @DirR  FLOAT;

    -- Convert from degrees to radians
    SET @Lat1R = RADIANS(@Lat);
    SET @Lon1R = RADIANS(@Lon);

    IF @Unit = 'km'
        SET @MaxDistR = @MaxDist * PI() / 20001.6;
    ELSE
        SET @MaxDistR = @MaxDist * PI() / 12428.418038654259126700071581961;

    -- Determine minimum and maximum latitude and longitude
    -- Calculate latitude of north boundary
    SET @DirR  = RADIANS(0e0);
    SET @Lat2R = ASIN( SIN(@Lat1R) * COS(@MaxDistR)
                     + COS(@Lat1R) * SIN(@MaxDistR) * COS(@DirR));
    -- Convert back to degrees
    SET @LatMax = DEGREES(@Lat2R);

    -- Calculate longitude of west boundary
    SET @DirR  = RADIANS(90e0);
    -- Need latitude first
    SET @Lat2R = ASIN( SIN(@Lat1R) * COS(@MaxDistR)
                     + COS(@Lat1R) * SIN(@MaxDistR) * COS(@DirR));
    -- Calculate longitude difference.
    SET @DLonR = ATN2(SIN(@DirR)  * SIN(@MaxDistR) * COS(@Lat1R),
                      COS(@MaxDistR) - SIN(@Lat1R) * SIN(@Lat2R));
    -- Calculate longitude of new point - ensure result is between -PI and PI.
    SET @Lon2R = ( CAST(@Lon1R - @DLonR + PI() AS DECIMAL(38,37))
                 % CAST(2*PI() AS DECIMAL(38,37)))
                 - PI();
    -- Convert back to degrees
    SET @LonMin = DEGREES(@Lon2R);

    -- Calculate latitude of south boundary
    SET @DirR  = RADIANS(180e0);
    SET @Lat2R = ASIN( SIN(@Lat1R) * COS(@MaxDistR)
                     + COS(@Lat1R) * SIN(@MaxDistR) * COS(@DirR));
    -- Convert back to degrees
    SET @LatMin = DEGREES(@Lat2R);

    -- Calculate longitude of west boundary
    SET @DirR  = RADIANS(-90e0);
    -- Need latitude first
    SET @Lat2R = ASIN( SIN(@Lat1R) * COS(@MaxDistR)
                     + COS(@Lat1R) * SIN(@MaxDistR) * COS(@DirR));
    -- Calculate longitude difference.
    SET @DLonR = ATN2(SIN(@DirR)  * SIN(@MaxDistR) * COS(@Lat1R),
                      COS(@MaxDistR) - SIN(@Lat1R) * SIN(@Lat2R));
    -- Calculate longitude of new point - ensure result is between -PI and PI.
    SET @Lon2R = ( CAST(@Lon1R - @DLonR + PI() AS DECIMAL(38,37))
                 % CAST(2*PI() AS DECIMAL(38,37)))
                 - PI();
    -- Convert back to degrees
    SET @LonMax = DEGREES(@Lon2R);

    -- Search neighborhood within boundaries
    WITH PlacePlusDistance
    AS
    (
        SELECT
            PlaceName,
            State,
            dbo.DistCLR (Lat, Lon, @Lat, @Lon, @Unit) AS Dist
        FROM Place
        WHERE
            Lat BETWEEN @LatMin AND @LatMax
            AND Lon BETWEEN @LonMin AND @LonMax
    )
    INSERT INTO @Neighbors
    (
        PlaceName,
        State,
        Dist
    )
    SELECT
        PlaceName,
        State,
        Dist
    FROM PlacePlusDistance
    WHERE Dist < @MaxDist;
    RETURN;
END;
GO

-- Find cities in Texas that are 5 to 10 kilometers apart, using the T-SQL bounding box function.
SELECT
    p.PlaceName AS pPlace,
    p.State AS pState,
    n.PlaceName,
    n.State,
    n.Dist
FROM Place AS p
CROSS APPLY dbo.GetNeighbors(p.Lat, p.Lon, 10, 'km') AS n
WHERE
    p.State = 'TX'
    AND n.State = 'TX'
    AND n.Dist > 5;
GO

-- Find places in a 10 kilometer radius, using the T-SQL bounding box function.
DECLARE
    @Lat FLOAT,
    @Lon FLOAT,
    @MaxDist FLOAT;

SET @Lat = 47.622;
SET @Lon = -122.35;
SET @MaxDist = 10.0;

SELECT
    PlaceName,
    State,
    CAST(Dist AS decimal(6,4)) AS Distance
FROM dbo.GetNeighbors (@Lat, @Lon, @MaxDist, 'km')
ORDER BY Dist ASC;
GO

-- Find places in a 10 kilometer radius by using the CLR bounding box function.
DECLARE
    @Lat FLOAT,
    @Lon FLOAT,
    @MaxDist FLOAT;

SET @Lat = 47.622;
SET @Lon = -122.35;
SET @MaxDist = 10.0;

SELECT
    PlaceName,
    State,
    CAST(Dist AS decimal(6,4)) AS Distance
FROM dbo.CLRNeighbors (@Lat, @Lon, @MaxDist, 'km')
ORDER BY Dist ASC;
GO

-- Get average performance measurements after discarding highest and lowest 10%.
WITH RankedResults
AS
(
    SELECT
        TestGroup,
        TestName,
        CONVERT(FLOAT, Duration) / Repetitions AS AvgDuration,
        ROW_NUMBER () OVER (
            PARTITION BY TestGroup, TestName
            ORDER BY CONVERT(FLOAT, Duration) / Repetitions
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY TestGroup, TestName
        ) AS cnt
    FROM TestResults
)
SELECT
     TestGroup,
    TestName,
    AVG(AvgDuration) AS AvgDur,
    MAX(AvgDuration) AS MaxDur,
    MIN(AvgDuration) AS MinDur,
    (MAX(AvgDuration) - MIN(AvgDuration)) / AVG(AvgDuration) AS MaxDiff
FROM RankedResults
WHERE
    rn BETWEEN FLOOR((cnt + 10) * 0.1)
    AND CEILING(cnt * 0.9)
GROUP BY
    TestGroup,
    TestName
ORDER BY
    TestGroup,
    AvgDur ASC;
GO

-- Find nearest neighbor for places in Illinois, using CLR distance function.
SELECT
    f.PlaceName AS PlaceFrom,
    f.State AS StateFrom,
    t.PlaceName AS PlaceTo,
    t.State AS StateTo,
    t.Dist
FROM Place AS f
OUTER APPLY
(
    SELECT TOP (1)
        PlaceName,
        State,
        dbo.DistCLR (f.Lat, f.Lon, p.Lat, p.Lon, 'km') AS Dist
    FROM Place AS p
    WHERE
        -- Place is always nearest to itself - exclude this row
        p.HtmID <> f.HtmID
        -- Filter below is only to speed up testing
        AND p.State = 'IL'
    ORDER BY Dist
) AS t
-- Filter below is only to speed up testing
WHERE f.State = 'IL';
GO

-- Find nearest neighbor for places no more than 20 km apart in Illinois, using CLR bounding box function.
DECLARE @MaxDist FLOAT;
SET @MaxDist = 20.0;

SELECT
    f.PlaceName AS PlaceFrom,
    f.State AS StateFrom,
    t.PlaceName AS PlaceTo,
    t.State AS StateTo,
    t.Dist
FROM Place AS f
CROSS APPLY
(
    SELECT TOP (1)
        n.PlaceName,
        n.State,
        n.Dist
    FROM dbo.CLRNeighbors (f.Lat, f.Lon, @MaxDist, 'km') AS n
    WHERE
        -- Place is always nearest to itself - exclude this row
        n.Dist <> 0
        -- Filter below is only to speed up testing
        AND n.State = 'IL'
    ORDER BY n.Dist
) AS t
-- Filter below is only to speed up testing
WHERE f.State = 'IL';
GO

-- Find nearest neighbor for places no more than 20 km apart, using CLR bounding box function.
DECLARE @MaxDist FLOAT;
SET @MaxDist = 20.0;

SELECT
    f.PlaceName AS PlaceFrom,
    f.State AS StateFrom,
    t.PlaceName AS PlaceTo,
    t.State AS StateTo,
    t.Dist
FROM Place AS f
CROSS APPLY
(
    SELECT TOP (1)
        n.PlaceName,
        n.State,
        n.Dist
    FROM dbo.CLRNeighbors (f.Lat, f.Lon, @MaxDist, 'km') AS n
    WHERE
        -- Place is always nearest to itself - exclude this row
        n.Dist <> 0
        -- Filter below is only to speed up testing
        AND n.State = 'IL'
    ORDER BY n.Dist
) AS t
-- Filter below is only to speed up testing
WHERE f.State = 'IL';
GO

-- Find nearest neighbor for ALL places, using dynamic bounding box algorithm in inline T-SQL.
DECLARE @top int;
SET @top = 31;
WITH PlacePlusMaxDist
AS
(
    SELECT
        p.PlaceName,
        p.State,
        p.Lat,
        p.Lon,
        (
            SELECT MIN(Dist) + 0.0001
            FROM
            (
                SELECT Dist
                FROM
                (
                    SELECT TOP(@top)
                        dbo.DistCLR(p.Lat, p.Lon, Lat, Lon, 'km') AS Dist
                    FROM Place
                    WHERE Lon > p.Lon
                    ORDER BY Lon ASC
                ) AS East

                UNION ALL

                SELECT Dist
                FROM
                (
                    SELECT TOP(@top)
                        dbo.DistCLR(p.Lat, p.Lon, Lat, Lon, 'km') AS Dist
                    FROM Place
                    WHERE Lon < p.Lon
                    ORDER BY Lon DESC
                ) AS West
            ) AS Near
        ) AS MaxDist
    FROM Place AS p
)
SELECT
    f.PlaceName AS PlaceFrom,
    f.State AS StateFrom,
    t.PlaceName AS PlaceTo,
    t.State AS StateTo,
    t.Dist
FROM PlacePlusMaxDist AS f
CROSS APPLY
(
    SELECT TOP (1)
        n.PlaceName,
        n.State,
        n.Dist
    FROM dbo.CLRNeighbors (f.Lat, f.Lon, f.MaxDist, 'km') AS n
    -- Place is always nearest to itself - exclude this row
    WHERE n.Dist <> 0
    ORDER BY n.Dist
) AS t;
GO

-- Find nearest neighbor for ALL places, using CLR implementation of dynamic bounding box.
SELECT
    f.PlaceName AS PlaceFrom,
    f.State AS StateFrom,
    t.PlaceName AS PlaceTo,
    t.State AS StateTo,
    t.Dist
FROM Place AS f
CROSS APPLY dbo.CLRDynamicBB(f.Lat, f.Lon, 'km') AS t;
GO

-- Take a peek at the contents of the Place table, including the HtmID column.
SELECT
    PlaceName,
    State,
    Lat,
    Lon,
    HtmID
FROM Place;
GO

-- Convert latitude and longitude to numeric and string representation of HtmID.
DECLARE
    @Lat FLOAT,
    @Lon FLOAT;
SET @Lat = 47.622;
SET @Lon = -122.35;
SELECT
    dbo.fHtmLatLon(@Lat,@Lon) AS "HtmID numeric",
    dbo.fHtmToString(dbo.fHtmLatLon(@Lat,@Lon)) AS "HtmID string";
GO

-- Calculate the distance between Seattle and Redmond, using distance function supplied in the HTM library.
WITH Seattle AS
(
    SELECT Lat, Lon
    FROM Place
    WHERE
        PlaceName = 'Seattle'
        AND State = 'WA'
)
,Redmond AS
(
    SELECT Lat, Lon
    FROM Place
    WHERE
        PlaceName = 'Redmond'
        AND State = 'WA'
)
SELECT
   dbo.fDistanceLatLon(s.Lat,s.Lon,r.Lat,r.Lon) * 1.852 AS DistKilometers,
   dbo.fDistanceLatLon(s.Lat,s.Lon,r.Lat,r.Lon) * 1.852 / 1.609344 AS DistMiles
FROM Seattle AS s
CROSS JOIN Redmond AS r;
GO

-- Find average distance from Michigan place to non-Michigan place for performance comparison.
DECLARE @Start DATETIME;
SET @Start = CURRENT_TIMESTAMP;

SELECT AVG(dbo.fDistanceLatLon(a.Lat,a.Lon,b.Lat,b.Lon) * 1.852) AS MaxDistKm
FROM Place AS a
CROSS JOIN Place AS b
WHERE
    a.State = 'MI'
    AND b.State <> 'MI';

SELECT DATEDIFF(ms, @Start, CURRENT_TIMESTAMP);
GO

-- Find places in a 10 kilometer radius by using the neighborhod search function supplied in the HTM library.
DECLARE
    @Lat FLOAT,
    @Lon FLOAT,
    @MaxDist FLOAT;

SET @Lat = 47.622;
SET @Lon = -122.35;
SET @MaxDist = 10.0;

-- Convert max distance to nautical miles.
DECLARE @MaxDistNM FLOAT;
SET @MaxDistNM = @MaxDist / 1.852;

SELECT
    PlaceName,
    State,
    CAST(distance * 1.852 AS decimal(6,4)) AS Dist
FROM dbo.fHtmNearbyLatLon('P', @Lat, @Lon, @MaxDistNM) AS I
INNER JOIN Place ON I.HtmID = Place.HtmID
ORDER BY Dist ASC;
GO

-- Convert min and max distance to nautical miles.
DECLARE
    @MinDistNM FLOAT,
    @MaxDistNM FLOAT;
SET @MinDistNM = 5.0 / 1.852;
SET @MaxDistNM = 10.0 / 1.852;

SELECT
    p.PlaceName AS pPlace,
    p.State AS pState,
    n.PlaceName,
    n.State,
    i.distance * 1.852 AS Dist
FROM Place AS p
CROSS APPLY dbo.fHtmNearbyLatLon('P', p.Lat, p.Lon, @MaxDistNM) AS i
INNER JOIN Place AS n ON i.HtmID = n.HtmID
WHERE
    p.State = 'TX'
    AND n.State = 'TX'
    AND i.distance > @MinDistNM;
GO

-- Find cities in Texas that are 5 to 10 kilometers apart, using the neighborhod search function supplied in the HTM library.
-- Convert min and max distance to nautical miles.
DECLARE
    @MinDistNM FLOAT,
    @MaxDistNM FLOAT;
SET @MinDistNM = 5.0 / 1.852;
SET @MaxDistNM = 10.0 / 1.852;

SELECT
    p.PlaceName AS pPlace,
    p.State AS pState,
    n.PlaceName,
    n.State,
    i.distance * 1.852 AS Dist
FROM Place AS p
CROSS APPLY dbo.fHtmNearbyLatLon('P', p.Lat, p.Lon, @MaxDistNM) AS i
INNER JOIN Place AS n ON i.HtmID = n.HtmID
WHERE
    p.State = 'TX'
    AND n.State = 'TX'
    AND i.distance > @MinDistNM;
GO

-- Create improved version of the neighborhod search function as supplied in the HTM library.
CREATE FUNCTION dbo.fHtmNearbyLatLon2
(
    @Lat FLOAT,
    @Lon FLOAT,
    @MaxDist FLOAT,
    @Unit CHAR(2) = 'km'
)
RETURNS @Neighbors TABLE
(
    PlaceName VARCHAR(100) NOT NULL,
    State CHAR(2) NOT NULL,
    Dist FLOAT NOT NULL
)
AS
BEGIN
    -- Convert max distance to nautical miles.
    DECLARE @MaxDistNM FLOAT;
    IF @Unit = 'km'
        SET @MaxDistNM = @MaxDist / 1.852;
    ELSE
        SET @MaxDistNM = @MaxDist * 1.609344 / 1.852;

    -- Search all trixels in circular area around center
    WITH PlacePlusDistance
    AS
    (
        SELECT
            p.PlaceName,
            p.State,
            dbo.DistCLR (p.Lat, p.Lon, @Lat, @Lon, @Unit) AS Dist
        FROM dbo.fHtmCoverCircleLatLon(@Lat, @Lon, @MaxDistNM) AS c
        INNER JOIN Place AS p
            ON p.HtmID BETWEEN c.HtmIDStart AND c.HtmIDEnd
    )
    INSERT INTO @Neighbors
    (
        PlaceName,
        State,
        Dist
    )
    SELECT
        PlaceName,
        State,
        Dist
    FROM PlacePlusDistance
    WHERE Dist < @MaxDist;

    RETURN;
END;
GO

-- Find places in a 10 kilometer radius by using the improved version of the HTM neighborhod search function.
DECLARE
    @Lat FLOAT,
    @Lon FLOAT,
    @MaxDist FLOAT;
SET @Lat = 47.622;
SET @Lon = -122.35;
SET @MaxDist = 10;

SELECT
    PlaceName,
    State,
    CAST(Dist AS decimal(6,4)) AS Distance
FROM dbo.fHtmNearbyLatLon2(@Lat,@Lon,@MaxDist,'km')
ORDER BY Dist ASC;
GO

-- Find cities in Texas that are 5 to 10 kilometers apart, using the improved version of the HTM neighborhod search function.
SELECT
    p.PlaceName AS pPlace,
    p.State AS pState,
    n.PlaceName,
    n.State,
    n.Dist
FROM Place AS p
CROSS APPLY dbo.fHtmNearbyLatLon2(p.Lat, p.Lon, 10, 'km') AS n
WHERE
    p.State = 'TX'
    AND n.State = 'TX'
    AND n.Dist > 5;
GO

-- Show the trixel ranges that define a 0.5 nautical mile radius circle around Denver.
SELECT
    dbo.fHtmToString(HtmIDStart) AS HtmIDStart,
    dbo.fHtmToString(HtmIDEnd) AS HtmIDEnd,
    HtmIDEnd - HtmIDStart + 1 AS NumberOfTrixels
FROM dbo.fHtmCoverCircleLatLon(39.768035,-104.872655,0.5);
GO

-- Create a function to test if it's better to include all trixels between lowest and highest HtmID.
CREATE FUNCTION dbo.fHtmNearbyLatLon3
(
    @Lat FLOAT,
    @Lon FLOAT,
    @MaxDist FLOAT,
    @Unit CHAR(2) = 'km'
)
RETURNS @Neighbors TABLE
(
    PlaceName VARCHAR(100) NOT NULL,
    State CHAR(2) NOT NULL,
    Dist FLOAT NOT NULL
)
AS
BEGIN
    -- Convert max distance to nautical miles.
    DECLARE @MaxDistNM FLOAT;
    IF @Unit = 'km'
        SET @MaxDistNM = @MaxDist / 1.852;
    ELSE
        SET @MaxDistNM = @MaxDist * 1.609344 / 1.852;

    -- Search all trixels in circular area around center
    WITH PlacePlusDistance
    AS
    (
        SELECT
            p.PlaceName,
            p.State,
            dbo.DistCLR (p.Lat, p.Lon, @Lat, @Lon, @Unit) AS Dist
        FROM
        (
            SELECT
                MIN(HtmIDStart) AS HtmIDStart,
                MAX(HtmIDEnd) AS HtmIDEnd
            FROM dbo.fHtmCoverCircleLatLon(@Lat, @Lon, @MaxDistNM)
        ) AS c
        INNER JOIN Place AS p
            ON p.HtmID BETWEEN c.HtmIDStart AND c.HtmIDEnd
    )
    INSERT INTO @Neighbors
    (
        PlaceName,
        State,
        Dist
    )
    SELECT
        PlaceName,
        State,
        Dist
    FROM PlacePlusDistance
    WHERE Dist < @MaxDist;

    RETURN;
END;
GO

-- Create adapted version of HTM nearest neighbor search that excludes distance 0.
CREATE FUNCTION dbo.fHtmNearestLatLonNot0(@type char(1), @Lat float, @Lon float)
-------------------------------------------------------------
--/H Returns table of objects of the given type within @r arcmins of a ra/dec point.
-------------------------------------------------------------
--/T <li> Lat float NOT NULL,          --/D Latitude (decimal degrees) 
--/T <li> Lon float NOT NULL,         --/D Longitude (decimal degrees) 
--/T <p> One object is returned. 
--/T <br>returned table has the same format as the spatail index (minus the type field):  
--/T <li> htmID bigint,               -- Hierarchical Trangular Mesh id of this object
--/T <li> Lat, Lon float not null,    -- Latitude and Longitude (dec/ra) of point.   
--/T <li> x,y,z float not null,       -- x,y,z of unit vector to this object
--/T <li> objID bigint,               -- object ID in SpatialIndex table. 
--/T <li> distance float              -- distance in arc minutes to this object from the ra,dec.
--/T <br> Sample call to find nearest place to Baltimore (which is Baltimore (!)). 
--/T <br><samp>
--/T <br> select distance, Place.*
--/T <br> from fHtmNearestLatLon('P', 39.3, -76.6) I join Place on I.objID = Place.HtmID
--/T </samp>  
--/T <br>see also fHtmNearbyLatLon, fHtmNearbyEq, fHtmNearestXYZ
-------------------------------------------------------------
  returns @SpatialIndex table (
					HtmID	bigint NOT NULL,
					Lat		float  NOT NULL,
					Lon		float  NOT NULL,
					x		float  NOT NULL,
					y		float  NOT NULL,
					z		float  NOT NULL,
 					ObjID	bigint NOT NULL,
					distance float NOT NULL -- distance in arc minutes
  ) as begin
	declare @x float, @y float, @z float, @r  float
	select	@x = cos(radians(@Lat))*cos(radians(@Lon)),
			@y = cos(radians(@Lat))*sin(radians(@Lon)),
			@z = sin(radians(@Lat)),	
			@r = 1
-- Try r = 1, 4, 14,.... till you find a non null set.
-- do the spatial join using the HTM cover. 
retry:
	insert @SpatialIndex 
		select top 1 
	    HtmID, 
	    Lat,Lon,
	    x,y,z,
	    ObjID,
 	    2*degrees(asin(sqrt(power(@x-x,2)+power(@y-y,2)+power(@z-z,2))/2))*60 
	    --sqrt(power(@x-x,2)+power(@y-y,2)+power(@z-z,2))/PI()/3 
	    from fHtmCoverCircleXyz(@x,@y,@z, @r) join SpatialIndex 
			on HtmID BETWEEN  HtmIDStart AND HtmIDEnd  
            and [Type]  = @type
--          this clause is simplified since it is innner loop.
--	        and( (2*DEGREES(ASIN(sqrt(power(@x-x,2)+power(@y-y,2)+power(@z-z,2))/2))*60)< @r)
			and (power(@x-x,2)+power(@y-y,2)+power(@z-z,2)) < power(2*sin(radians(@r/120)),2) 
-- The only modification of the original is the extra line below
WHERE Lat <> @Lat OR Lon <> @Lon
		order by (2*degrees(asin(sqrt(power(@x-x,2)+power(@y-y,2)+power(@z-z,2))/2))*60) asc
		OPTION(FORCE ORDER, LOOP JOIN)
		
	if (@@rowcount = 0)
		begin
		set @r = @r * 4
		goto retry
		end
	return
	end
GO

-- Find nearest neighbor for ALL places, using adapted version of HTM nearest neighbor function.
SELECT
    f.PlaceName AS PlaceFrom,
    f.State AS StateFrom,
    t.PlaceName AS PlaceTo,
    t.State AS StateTo,
    i.distance * 1.852 AS Dist
FROM Place AS f
CROSS APPLY dbo.fHtmNearestLatLonNot0('P', f.Lat, f.Lon) AS i
INNER JOIN Place AS t ON i.HtmID = t.HtmID;
GO

-- Create improved version of the nearest neighbor search function as supplied in the HTM library.
CREATE FUNCTION dbo.fHtmNearestLatLon2
(
    @Lat FLOAT,
    @Lon FLOAT,
    @Unit CHAR(2) = 'km'
)
RETURNS @Neighbors TABLE
(
    PlaceName VARCHAR(100) NOT NULL,
    State CHAR(2) NOT NULL,
    Dist FLOAT NOT NULL
)
AS
BEGIN
    -- Try first with a maximum distance of 1 nautical mile.
    -- Try distance = 1, 4, 16,.... till you find a nonnull set.
    DECLARE
        @MaxDistNM FLOAT,
        @MaxDist FLOAT;
    SET @MaxDistNM = 1;

retry:
    -- Convert nautical miles to kilometers or miles.
    IF @Unit = 'km'
        SET @MaxDist = @MaxDistNM * 1.852;
    ELSE
        SET @MaxDist = @MaxDistNM * 1.852 / 1.609344;

    WITH PlacePlusDistance
    AS
    (
        SELECT
            p.PlaceName,
            p.State,
            dbo.DistCLR (p.Lat, p.Lon, @Lat, @Lon, @Unit) AS Dist
        FROM dbo.fHtmCoverCircleLatLon(@Lat, @Lon, @MaxDistNM) AS c
        INNER JOIN Place AS p
            ON p.HtmID BETWEEN c.HtmIDStart AND c.HtmIDEnd
        -- Place is always nearest to itself - exclude this row
        WHERE
            p.Lat <> @Lat
            OR p.Lon <> @Lon
    )
    INSERT INTO @Neighbors
    (
        PlaceName,
        State,
        Dist
    )
    SELECT TOP (1)
        PlaceName,
        State,
        Dist
    FROM PlacePlusDistance
    WHERE Dist < @MaxDist
    ORDER BY Dist;

    -- If no rows are found, try again with larger radius.
    IF @@ROWCOUNT = 0
    BEGIN
        SET @MaxDistNM = @MaxDistNM * 4;
        GOTO retry;
    END;
    RETURN;
END;
GO

-- Find nearest neighbor for ALL places, using improved version of HTM nearest neighbor function.
SELECT
    f.PlaceName AS PlaceFrom,
    f.State AS StateFrom,
    t.PlaceName AS PlaceTo,
    t.State AS StateTo,
    t.Dist
FROM Place AS f
CROSS APPLY dbo.fHtmNearestLatLon2(f.Lat, f.Lon, 'km') AS t;
GO
