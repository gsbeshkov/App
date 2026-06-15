import os

from urllib.parse import quote_plus
import requests
from flask import Flask, request, Response, jsonify
from pymongo import MongoClient
from pymongo.errors import PyMongoError

SERVER_HOST = os.environ.get("SERVER_HOST", "0.0.0.0")
SERVER_PORT = int(os.environ.get("SERVER_PORT", 5000))

PROXY_URL = os.environ.get("PROXY_URL")
MONGO_HOST = os.environ.get("MONGO_HOST")
MONGO_DB = os.environ.get("MONGO_DB")
MONGO_USER = os.environ.get("MONGO_USER")
MONGO_PASSWORD = os.environ.get("MONGO_PASSWORD")

app = Flask(__name__)

if not PROXY_URL:
    raise RuntimeError("PROXY_URL environment variable is missing")

if not MONGO_HOST or not MONGO_DB or not MONGO_USER or not MONGO_PASSWORD:
    raise RuntimeError("MONGO_HOST, MONGO_DB ,MONGO_USER or MONGO_PASSWORD environment variable is missing")

mongo_url = "mongodb://%s:%s@%s" % (quote_plus(MONGO_USER), quote_plus(MONGO_PASSWORD), MONGO_HOST)

mongo_client = MongoClient(mongo_url)


@app.route("/proxy", methods=[
    "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"
])
def proxy():
    try:
        resp = requests.request(
            method=request.method,
            url=PROXY_URL,
            params=request.args,
            headers={"Content-Type": "application/json"},
            data=request.get_data(),
            allow_redirects=False,
            timeout=30,
        )

        return Response(
            resp.content,
            status=resp.status_code
        )

    except requests.RequestException as e:
        return jsonify({
            "status": "error",
            "message": str(e),
        }), 502

@app.route("/health", methods=["GET"])
def health():
    try:
        mongo_client[MONGO_DB].command("ping")

        return jsonify({
            "status": "healthy",
            "mongodb": "connected"
        }), 200

    except PyMongoError as e:
        return jsonify({
            "status": "unhealthy",
            "mongodb": "disconnected",
            "error": str(e)
        }), 417

if __name__ == "__main__":
    app.run(host=SERVER_HOST, port=SERVER_PORT)