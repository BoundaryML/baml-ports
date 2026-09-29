test "smoke_decode_any" {
    let d = decode<map<string, Any>>("a = 1\nb = \"x\"\n[t]\nc = [1, 2.5]\n[[aot]]\nz = 1979-05-27T07:32:00Z\n");
    let keys: string[] = [];
    for (let k in d.meta.keys()) {
        keys.push(k.to_string() + ":" + d.meta.type(k.parts));
    }
    assert.equal(keys.join(","), "a:Integer,b:String,t:Hash,t.c:Array,aot:ArrayHash,aot.z:Datetime")
}
