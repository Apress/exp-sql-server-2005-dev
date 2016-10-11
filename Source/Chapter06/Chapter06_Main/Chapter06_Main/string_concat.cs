using System;
using System.Data;
using System.Data.SqlClient;
using System.Data.SqlTypes;
using Microsoft.SqlServer.Server;
using System.Collections.Generic;


[Serializable]
[Microsoft.SqlServer.Server.SqlUserDefinedAggregate(
    Format.UserDefined, MaxByteSize=8000)]
public struct string_concat : IBinarySerialize
{
    private List<string> theStrings;

    public void Init()
    {
        theStrings = new List<string>();
    }

    public void Accumulate(SqlString Value)
    {
        if (!(Value.IsNull))
            theStrings.Add(Value.Value);
    }

    public void Merge(string_concat Group)
    {
        foreach (string theString in Group.theStrings)
            this.theStrings.Add(theString);
    }

    public SqlString Terminate()
    {
        string[] allStrings = theStrings.ToArray();
        string final = String.Join(",", allStrings);

        return new SqlString(final);
    }

    #region IBinarySerialize Members

    public void Read(System.IO.BinaryReader r)
    {
        int count = r.ReadInt32();
        this.theStrings = new List<string>(count);

        for (; count > 0; count--)
        {
            theStrings.Add(r.ReadString());
        }
    }

    public void Write(System.IO.BinaryWriter w)
    {
        w.Write(theStrings.Count);
        foreach (string s in theStrings)
            w.Write(s);
    }

    #endregion
}
