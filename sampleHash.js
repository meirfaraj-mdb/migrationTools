var i = 0;


// calculate the number of index to create
db.adminCommand({listDatabases: 1}).databases.forEach((d) => {
    // skip sys and test DB
    if (d.name === "local"||d.name === "config"||d.name === "admin"||d.name === "test") return;
db.getSiblingDB(d.name).getCollectionInfos().forEach((c) => {
    if (c.type !== "collection" || c.name === "system.views") return;
    dbCompare = {}
    const stats = db.getSiblingDB(d.name).getCollection(c.name).aggregate([
        { $sample: { size: 1000 } },
        {"$project": {h: {$toHashedIndexKey:"$$ROOT"}}}]).toArray();
    dbCompare[d.name+"."+c.name]=stats;
    print("dbCompare = '"+EJSON.stringify(dbCompare)+"'");
 });
});

