
// calculate the number of index to create
dbCompare=EJSON.parse(dbCompare, { relaxed:false})
for (const [key, value] of Object.entries(dbCompare)) {
  d={}
  c={}
  splt=key.split('.')
  d.name=splt[0]
  c.name=splt[1]
  c.type='collection'
  if (d.name === "local"||d.name === "config"||d.name === "admin"||d.name === "test") continue;
  if (c.type !== "collection" || c.name === "system.views") continue;
  cur = value
    res={};
    res['count']=cur.length
    res['ok']=0;
    res['nok']=[];
    while (cur.length) {
       next = cur.splice(0, Math.min(200,cur.length));
       next_keys = [];
       val = {}
       next.forEach(function(item) {
            next_keys.push(item._id);
            val[item._id]=EJSON.parse(item.h,{relaxed:true});
       });

       pipeline=[{ '$match': { _id: { '$in': next_keys } }},{"$project": {h: {$toHashedIndexKey:"$$ROOT"}}}];
       const stats = db.getSiblingDB(d.name).getCollection(c.name).aggregate(pipeline).toArray();
       if(stats.length!=0){
           stats.forEach( (r) =>{
                   if (r.h==val[r._id]){
                      res['ok'] = res['ok']+1;
                   }
                   else{
                      res['nok'].push(r._id);
                   }
           })
       }
   }
    dbCompare[d.name+"."+c.name] = res;
    if(res['nok'].length==0&&res['count']==res['ok']){
        delete(res['nok']);
        res['status']='ok';
    }
    else{
       if(res['nok'].length==0)
         delete(res['nok']);
       res['status']='nok';
       //print(pipeline)
    }
}
print(EJSON.stringify(dbCompare,{relaxed:true}));