FROM ubuntu

WORKDIR /app

COPY . .

ENTRYPOINT FLASK_APP=app.py flask run --host=0.0.0.0
