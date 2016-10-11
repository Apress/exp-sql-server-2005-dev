using System;
using System.Data;
using System.Data.SqlClient;
using System.Data.SqlTypes;
using Microsoft.SqlServer.Server;

public partial class StoredProcedures
{
    [Microsoft.SqlServer.Server.SqlProcedure]
    public static void MoveCLR
                 (SqlDouble Lat1, SqlDouble Lon1,
                  SqlDouble Dist, SqlDouble Dir,
                  out SqlDouble Lat2, out SqlDouble Lon2,
                  SqlString Unit)
    {
        // This is just a wrapper for the T-SQL interface.
        // Call the proc that does the real work.
        double Lat2d;
        double Lon2d;
        SpatialMove(Lat1.Value, Lon1.Value,
                    Dist.Value, Dir.Value,
                    (Unit.Value.Equals("mi")),
                    out Lat2d, out Lon2d);
        Lat2 = new SqlDouble(Lat2d);
        Lon2 = new SqlDouble(Lon2d);
    }

    public static void SpatialMove
                 (double Lat1, double Lon1,
                  double Dist, double Dir,
                  bool Miles,
                  out double Lat2, out double Lon2)
    {
        // Convert degrees to radians
        double Lat1R = Lat1 * Math.PI / 180;
        double Lon1R = Lon1 * Math.PI / 180;
        double DirR = Dir * Math.PI / 180;

        // Convert distance from km/mi to radians
        // Note: DistR = Distance in nautical miles * (pi / (180 * 60))
        //               One nautical mile is 1.852 kilometers, thus:
        //   or: DistR =(DistKM / 1.852) * pi / (180 * 60)
        //   or: DistR = DistKM * pi / (180 * 60 * 1.852)
        //   or: DistR = DistKM * pi / 20001.6
        // Since one mile is 1.609344 kilometers, the formula for miles is:
        //       DistR =(DistMI * 1.609344) * pi / 20001.6
        //   or: DistR = DistMI * pi / (20001.6 / 1.609344)
        //   or: DistR = DistMI * pi / 12428.418038654259126700071581961
        double DistR = Dist * Math.PI 
                     / (Miles ? 12428.418038654259126700071581961 : 20001.6);

        // Calculate new latitude
        double Lat2R = Math.Asin(Math.Sin(Lat1R) * Math.Cos(DistR)
                   + Math.Cos(Lat1R) * Math.Sin(DistR) * Math.Cos(DirR));
        // Convert results back to degrees
        Lat2 = Lat2R * 180 / Math.PI;

        // Calculate longitude difference
        double DLonR = Math.Atan2(Math.Sin(DirR)
                                * Math.Sin(DistR) * Math.Cos(Lat1R),
                                  Math.Cos(DistR)
                                - Math.Sin(Lat1R) * Math.Sin(Lat2R));
        // Calculate new longitude - ensure result is between -PI and PI
        double Lon2R = ((Lon1R - DLonR + Math.PI) % (2 * Math.PI)) - Math.PI;
        // Convert results back to degrees
        Lon2 = Lon2R * 180 / Math.PI;
    }
};
