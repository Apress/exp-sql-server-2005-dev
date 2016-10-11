using System;
using System.Data;
using System.Data.SqlClient;
using System.Data.SqlTypes;
using Microsoft.SqlServer.Server;
using System.Collections;
using System.Collections.Generic;

public partial class UserDefinedFunctions
{
    public struct BBox
    {
        public SqlString _PlaceName;
        public SqlString _State;
        public SqlDouble _Dist;
        public BBox(SqlString PlaceName, SqlString State, SqlDouble Dist)
        {
            _PlaceName = PlaceName;
            _State = State;
            _Dist = Dist;
        }
    }

    [Microsoft.SqlServer.Server.SqlFunction(IsDeterministic = true,
      DataAccess = DataAccessKind.Read, FillRowMethodName = "FillRow",
      TableDefinition = "PlaceName NVARCHAR(100), State NCHAR(2), Dist FLOAT")]
    public static IEnumerable CLRNeighbors(SqlDouble LatIn, SqlDouble LonIn,
                                           SqlDouble MaxDistIn, SqlString Unit)
    {
        double Lat = LatIn.Value, Lon = LonIn.Value, MaxDist = MaxDistIn.Value;
        double LatMax, LatMin, LonMax, LonMin, Dummy;
        bool Miles = (Unit.Value.Equals("mi"));
        // Calculate minimum and maximum longitude and latitude
        StoredProcedures.SpatialMove(Lat, Lon, MaxDist, 0,   // North
                                     Miles, out LatMax, out Dummy);
        StoredProcedures.SpatialMove(Lat, Lon, MaxDist, 90,  // West
                                     Miles, out Dummy, out LonMin);
        StoredProcedures.SpatialMove(Lat, Lon, MaxDist, 180, // South
                                     Miles, out LatMin, out Dummy);
        StoredProcedures.SpatialMove(Lat, Lon, MaxDist, -90, // East
                                     Miles, out Dummy, out LonMax);

        List<BBox> _BBdata = new List<BBox>();

        using (SqlConnection conn =
            new SqlConnection("context connection = true"))
        {
            SqlCommand comm = 
                new SqlCommand("SELECT PlaceName, State, Lat, Lon "
                             + "FROM dbo.Place "
                             + "WHERE Lat BETWEEN @LatMin AND @LatMax "
                             + "AND Lon BETWEEN @LonMin AND @LonMax", conn);
            comm.Parameters.Add("@LatMin", SqlDbType.Float);
            comm.Parameters[0].Value = LatMin;
            comm.Parameters.Add("@LatMax", SqlDbType.Float);
            comm.Parameters[1].Value = LatMax;
            comm.Parameters.Add("@LonMin", SqlDbType.Float);
            comm.Parameters[2].Value = LonMin;
            comm.Parameters.Add("@LonMax", SqlDbType.Float);
            comm.Parameters[3].Value = LonMax;

            conn.Open();
            SqlDataReader reader = comm.ExecuteReader();

            while (reader.Read())
            {
                double Lat2 = reader.GetDouble(2);
                double Lon2 = reader.GetDouble(3);
                double Dist = SpatialDist(Lat, Lon, Lat2, Lon2, Miles);
                if (Dist <= MaxDist)
                {
                    SqlString PlaceName = reader.GetSqlString(0);
                    SqlString State = reader.GetSqlString(1);
                    BBox BBnew = new BBox(PlaceName,
                                            State,
                                            (SqlDouble)Dist);
                    _BBdata.Add(BBnew);
                }
            }
        }

        return (IEnumerable)_BBdata;
    }

    [Microsoft.SqlServer.Server.SqlFunction(IsDeterministic = true,
      DataAccess = DataAccessKind.Read, FillRowMethodName = "FillRow",
      TableDefinition = "PlaceName NVARCHAR(100), State NCHAR(2), Dist FLOAT")]
    public static IEnumerable CLRDynamicBB(SqlDouble LatIn, SqlDouble LonIn,
                                           SqlString Unit)
    {
        double Lat = LatIn.Value, Lon = LonIn.Value, MaxDist = 100000;
        double LatMax, LatMin, LonMax, LonMin, Dummy;
        bool Miles = (Unit.Value.Equals("mi"));
        double Lat2, Lon2, Dist;
        BBox[] BBdata = new BBox[1];

        // Find MaxDist to use; try Tries locations east and west,
        //                      but stop at Threshold.
        using (SqlConnection conn = new SqlConnection("context connection = true"))
        {
            conn.Open();

            // Sample some places
            SqlCommand comm1 = new SqlCommand("SELECT Lat, Lon FROM "
                          + "(SELECT TOP(26) Lat, Lon "
                          + "FROM dbo.Place WHERE Lon > @Lon "
                          + "ORDER BY Lon ASC) AS East "
                          + "UNION ALL SELECT Lat, Lon FROM "
                          + "(SELECT TOP(26) Lat, Lon "
                          + "FROM dbo.Place WHERE Lon < @Lon "
                          + "ORDER BY Lon DESC) AS West", conn);
            comm1.Parameters.Add("@Lon", SqlDbType.Float);
            comm1.Parameters[0].Value = Lon;

            using (SqlDataReader reader = comm1.ExecuteReader())
            {
                // Bail out when below threshold
                while ((MaxDist > 8.5) && (reader.Read()))
                {
                    Lat2 = reader.GetDouble(0);
                    Lon2 = reader.GetDouble(1);
                    Dist = SpatialDist(Lat, Lon, Lat2, Lon2, Miles);
                    if (Dist <= MaxDist)
                        MaxDist = Dist;
                }
            }

            // Add tiny bit to MinDist to fence off rounding errors
            MaxDist += 0.001;
            // Calculate minimum and maximum longitude and latitude for MaxDist
            StoredProcedures.SpatialMove(Lat, Lon, MaxDist, 0,   // North
                                         Miles, out LatMax, out Dummy);
            StoredProcedures.SpatialMove(Lat, Lon, MaxDist, 90,  // West
                                         Miles, out Dummy, out LonMin);
            StoredProcedures.SpatialMove(Lat, Lon, MaxDist, 180, // South
                                         Miles, out LatMin, out Dummy);
            StoredProcedures.SpatialMove(Lat, Lon, MaxDist, -90, // East
                                         Miles, out Dummy, out LonMax);

            // Fetch rows within the dynamic bounding box
            SqlCommand comm2 = new SqlCommand("SELECT PlaceName, State, Lat, Lon "
                                   + "FROM dbo.Place "
                                   + "WHERE Lat BETWEEN @LatMin AND @LatMax "
                                   + "AND Lon BETWEEN @LonMin AND @LonMax", conn);
            comm2.Parameters.Add("@LatMin", SqlDbType.Float);
            comm2.Parameters[0].Value = LatMin;
            comm2.Parameters.Add("@LatMax", SqlDbType.Float);
            comm2.Parameters[1].Value = LatMax;
            comm2.Parameters.Add("@LonMin", SqlDbType.Float);
            comm2.Parameters[2].Value = LonMin;
            comm2.Parameters.Add("@LonMax", SqlDbType.Float);
            comm2.Parameters[3].Value = LonMax;

            using (SqlDataReader reader = comm2.ExecuteReader())
            {
                // Find place with lowest non-zero distance
                double MinDist = MaxDist;

                while (reader.Read())
                {
                    Lat2 = reader.GetDouble(2);
                    Lon2 = reader.GetDouble(3);
                    if ((Lat2 != Lat) || (Lon2 != Lon))
                    {
                        Dist = SpatialDist(Lat, Lon, Lat2, Lon2, Miles);
                        if (Dist < MinDist)
                        {
                            MinDist = Dist;
                            BBdata[0]._PlaceName = reader.GetSqlString(0);
                            BBdata[0]._State = reader.GetSqlString(1);
                        }
                    }
                }
                BBdata[0]._Dist = MinDist;
            }
        }

        return (IEnumerable)BBdata;
    }

    public static void FillRow(Object obj, out SqlString PlaceName,
                               out SqlString State, out SqlDouble Dist)
    {
        BBox bb = (BBox)obj;
        PlaceName = bb._PlaceName;
        State = bb._State;
        Dist = bb._Dist;
    }
};