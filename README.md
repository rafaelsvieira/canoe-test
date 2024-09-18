# Canoe DevOps Tech Assessment

The repository has the goal to describe the solution of the exercise provided by Canoe.

## Set up

The next steps were tested using the follow configurations and tools version:

1. __Docker__: 27.0.3
2. __Python__: 3.12
3. __AWS CLI__: 2.15.14
4. __Terraform__: 1.5.7

## Task 1

### 1 - Rest API

To develop the API this project is using Python with [Flask](https://flask.palletsprojects.com/en/3.0.x/). The API has 3 endpoints:

1. `GET /hello_world`: Should return a 200 status code with `{ "message": "Hello World!" } JSON response`;
2. `GET /current_time?name=some_name`: Should return a 200 status code with `{ "timestamp": 1700000000, "message": "Hello some_name" }`;
3. `GET /healthcheck`: Should return a 200 status code to indicate that the service is healthy.

To create the previous routes the Flask library has a [router function](https://flask.palletsprojects.com/en/3.0.x/api/#flask.Flask.route) used as a decorator. So, each endpoint has a function with a decorator showing the request path. Besides that the port must be defined into the code and this project is using the port 5000.

### 2 - Docker image

The [python-latest](https://images.chainguard.dev/directory/image/python/overview) images base used are from [Chainguard](https://www.chainguard.dev/) because this company works to build security and shorter images. To build the app image this project is using two layers, the first to install the packages and the second to get the packages, run without root power and without unnecessary packages like bash or sh.

To build this image just run the follow commands:

```sh
$ cd src/
$ docker build . -t canoe-api:latest
```

### 3 - Running locally

After execute the previous command and build the image, to run just execute the follow command:

```sh
$ docker run -d --name test -p 5000:5000 canoe-api:latest
```

To test the endpoint a simple `curl` can return the response.

```sh
$ curl -X GET -H "Content-Type: application/json" http://localhost:5000/healthcheck
```

If you want to follow the logs:

```sh
$ docker logs test -f
```

So, to stop and remove the container:

```sh
$ docker rm -f $(docker ps -aqf "name=^test$")
```

### 4 - Publish to ECR

To publish a image to ECR it's necessary have a AWS account, export the credentials and execute the follow commands:

```sh
$ aws ecr get-login-password --region region | docker login --username AWS --password-stdin aws_account_id.dkr.ecr.region.amazonaws.com
$ docker tag canoe-api:latest aws_account_id.dkr.ecr.region.amazonaws.com/my-repository:tag
$ docker push aws_account_id.dkr.ecr.region.amazonaws.com/my-repository:tag
```

The values `aws_account_id`, `region` and `my-repository:tag` should be changed to real values.

