#!/bin/bash
set -e

PROJECT_DIR="$(pwd)/elk_project"

echo "=== Создаём структуру каталогов ==="
mkdir -p "$PROJECT_DIR/nginx/logs"
cd "$PROJECT_DIR"

echo "=== docker-compose.yml ==="
cat > docker-compose.yml <<'EOF'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.12.2
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
    ports:
      - "9200:9200"

  kibana:
    image: docker.elastic.co/kibana/kibana:8.12.2
    container_name: kibana
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    ports:
      - "5601:5601"
    depends_on:
      - elasticsearch

  logstash:
    image: docker.elastic.co/logstash/logstash:8.12.2
    container_name: logstash
    volumes:
      - ./logstash.conf:/usr/share/logstash/pipeline/logstash.conf
    depends_on:
      - elasticsearch

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.12.2
    container_name: filebeat
    user: root
    command: ["filebeat", "-e", "-strict.perms=false"]
    volumes:
      - ./filebeat.yml:/usr/share/filebeat/filebeat.yml
      - ./nginx/logs:/var/log/nginx
    depends_on:
      - logstash

  nginx:
    image: nginx:alpine
    container_name: nginx
    volumes:
      - ./nginx/logs:/var/log/nginx
    ports:
      - "8080:80"
EOF

echo "=== logstash.conf ==="
cat > logstash.conf <<'EOF'
input {
  beats {
    port => 5044
  }
}

filter {
  grok {
    match => { "message" => "%{COMMONAPACHELOG}" }
  }
}

output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    index => "nginx-logs"
  }
  stdout { codec => rubydebug }
}
EOF

echo "=== filebeat.yml ==="
cat > filebeat.yml <<'EOF'
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/nginx/access.log

output.logstash:
  hosts: ["logstash:5044"]
EOF

echo "=== Перезапуск контейнеров ==="
docker compose down -v || true
docker compose up -d

echo "=== Ожидаем Elasticsearch ==="
until curl -s http://localhost:9200 >/dev/null; do
  echo -n "."
  sleep 2
done
echo " OK"

echo "=== Генерация тестовых nginx-запросов ==="
for i in {1..10}; do
  curl -s http://localhost:8080 > /dev/null
done

echo "=== Ждём Filebeat / Logstash ==="
sleep 10

echo
echo "=== Проверка индексов ==="
curl http://localhost:9200/_cat/indices?v

echo
echo "✅ ГОТОВО"
echo "Kibana → http://localhost:5601"

