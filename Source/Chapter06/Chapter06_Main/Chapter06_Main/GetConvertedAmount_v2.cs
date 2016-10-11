using System;
using System.Data;
using System.Data.SqlClient;
using System.Data.SqlTypes;
using Microsoft.SqlServer.Server;
using SafeDictionary;

public partial class UserDefinedFunctions2
{
    static readonly ThreadSafeDictionary<string, decimal> rates =
        new ThreadSafeDictionary<string, decimal>();

    [SqlFunction]
    public static SqlDecimal GetConvertedAmount_v2(
        SqlDecimal InputAmount,
        SqlString InCurrency,
        SqlString OutCurrency)
    {
        //Convert the input amount to the base
        decimal BaseAmount =
           GetRate(InCurrency.Value) *
           InputAmount.Value;

        //Return the converted base amount
        return (new SqlDecimal(
           GetRate(OutCurrency.Value) * BaseAmount));
    }

    private static decimal GetRate(string Currency)
    {
        return (rates[Currency]);
    }
};

