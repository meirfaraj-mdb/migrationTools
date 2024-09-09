
var i = 0;

colStats = {}

// calculate the number of index to create
db.adminCommand({listDatabases: 1}).databases.forEach((d) => {
    // skip sys and test DB
    if (d.name === "local"||d.name === "config"||d.name === "admin"||d.name === "test") return;
db.getSiblingDB(d.name).getCollectionInfos().forEach((c) => {
    if (c.type !== "collection" || c.name === "system.views") return;
    const stats = db.getSiblingDB(d.name).getCollection(c.name).stats();
    res = {};
    res['count']=stats.count
    res['icount']=stats.nindexes
  //  print("add "+c.name+" with"+res)
    colStats[d.name+"."+c.name]=res;
 });
});
print(JSON.stringify(colStats));

/*
var keys = Object.keys(colStats);
keys.sort();


for (var i=0; i<keys.length; i++) { 
    var key = keys[i];
    var value = colStats[key];
    print(""+key+","+value['count']+","+value['icount']);
} 
*/