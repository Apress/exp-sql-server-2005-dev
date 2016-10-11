using System;
using System.Data;
using System.Data.SqlClient;
using System.Data.SqlTypes;
using Microsoft.SqlServer.Server;
using System.Collections.Generic;
using SafeDictionary;

[Microsoft.SqlServer.Server.SqlUserDefinedAggregate(
    Format.UserDefined, MaxByteSize=16)]
public struct string_concat_2 : IBinarySerialize
{
    readonly static ThreadSafeDictionary<Guid, List<string>> theLists =
        new ThreadSafeDictionary<Guid, List<string>>();

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

    public void Merge(string_concat_2 Group)
    {
        foreach (string theString in Group.theStrings)
            this.theStrings.Add(theString);
    }

    //Make sure to use SqlChars if you use
    //VS deployment!
    public SqlChars Terminate()
    {
        string[] allStrings = theStrings.ToArray();
        string final = String.Join(",", allStrings);

        return new SqlChars(final);
    }

    #region IBinarySerialize Members

    public void Read(System.IO.BinaryReader r)
    {
        //Get the GUID from the stream
        Guid g = new Guid(r.ReadBytes(16));

        try
        {
            //Grab the collection of strings
            this.theStrings = theLists[g];
        }
        finally
        {
            //Clean up
            theLists.Remove(g);
        }
    }

    public void Write(System.IO.BinaryWriter w)
    {
        Guid g = Guid.NewGuid();

        try
        {
            //Add the local collection to the static dictionary
            theLists.Add(g, this.theStrings);

            //Persist the GUID
            w.Write(g.ToByteArray());
        }
        catch
        {
            //Try to clean up in case of exception
            if (theLists.ContainsKey(g))
                theLists.Remove(g);
        }
    }

    #endregion
}
