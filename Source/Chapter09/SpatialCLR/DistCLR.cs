using System;
using System.Data;
using System.Data.SqlClient;
using System.Data.SqlTypes;
using Microsoft.SqlServer.Server;

public partial class UserDefinedFunctions
{
    [Microsoft.SqlServer.Server.SqlFunction(IsDeterministic=true)]
    public static SqlDouble DistCLR
                 (SqlDouble Lat1, SqlDouble Lon1,
                  SqlDouble Lat2, SqlDouble Lon2, SqlString Unit)
    {
        // This is just a wrapper for the T-SQL interface.
        // Call the function that does the real work.
        double Dist = SpatialDist(Lat1.Value, Lon1.Value,
                                  Lat2.Value, Lon2.Value,
                                  (Unit.Value.Equals("mi")));
        return new SqlDouble(Dist);
    }


    public static double SpatialDist
                 (double Lat1, double Lon1,
                  double Lat2, double Lon2, bool Miles)
    {
        // Convert degrees to radians
        double Lat1R = Lat1 * Math.PI / 180;
        double Lon1R = Lon1 * Math.PI / 180;
        double Lat2R = Lat2 * Math.PI / 180;
        double Lon2R = Lon2 * Math.PI / 180;

        // Calculate distance
        double DistR =
            2 * Math.Asin(Math.Sqrt(Math.Pow(Math.Sin((Lat1R - Lat2R) / 2), 2)
             + (Math.Cos(Lat1R) * Math.Cos(Lat2R)
              * Math.Pow(Math.Sin((Lon1R - Lon2R) / 2), 2))));

        // Convert from radians to kilometers or miles
        double Dist = DistR
                    * (Miles ? 20001.6 / 1.609344 : 20001.6)
                    / Math.PI;

        return Dist;
    }
};