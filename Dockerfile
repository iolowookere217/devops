FROM ubuntu

RUN apt-get update
RUN apt-get install -y python3 python3-pip
RUN pip install flask

WORKDIR /app

COPY . .

EXPOSE 80 
EXPOSE 8080 
EXPOSE 8001 
EXPOSE 443

ENTRYPOINT FLASK_APP=/app/myapp.py flask run --host=0.0.0.0
 