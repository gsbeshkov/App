db = db.getSiblingDB("admin");

db.createUser({
    user: "proxyUser",
    pwd: "verySecPassw0rd",
    roles: [
        { role: "readWrite", db: "proxyApp" }
    ]
});
