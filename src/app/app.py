import json
import time
from flask import Flask, jsonify, request

app = Flask(__name__)

@app.route('/hello_world', methods=['GET'])
def hello_world():
    response = {
        'message': 'Hello, World!'
    }
    return jsonify(response), 200

@app.route('/current_time', methods=['GET'])
def current_time():
    querystring_name = request.args.get('name')
    user = 'anonymous'

    if querystring_name:
        user = querystring_name

    response = {
        'message': f'Hello {user}',
        'timestamp': time.time_ns()
    }

    return jsonify(response), 200

@app.route('/healthcheck', methods=['GET'])
def healthcheck():
    response = {
        'message': 'I\'m here!'
    }

    return jsonify(response), 200

if __name__ == '__main__':
   app.run(port=5000)