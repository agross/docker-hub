# docker-hub

[![](https://images.microbadger.com/badges/image/agross/hub.svg)](https://microbadger.com/images/agross/hub "Get your own image badge on microbadger.com")

This Dockerfile allows you to build images to deploy your own [Hub](http://www.jetbrains.com/hub/) instance. It has been tested on [Fedora 23](https://getfedora.org/) and [CentOS 7](https://www.centos.org/).

*Please remember to back up your data directories often, especially before upgrading to a newer version.*

## Test it

1. [Install docker.](http://docs.docker.io/en/latest/installation/)
2. Run the container. (Stop with CTRL-C.)

  ```sh
  docker run -it -p 8080:8080 agross/hub
  ```

3. Open your browser and navigate to `http://localhost:8080`.

## Run it as service on systemd

1. Decide where to put Hub data and logs. Set domain name/server name and the public port.

  ```sh
  HUB_DATA="/var/data/hub"
  HUB_LOGS="/var/log/hub"

  DOMAIN=example.com
  PORT=8010
  ```

2. Create directories to store data and logs outside of the container.

  ```sh
  mkdir --parents "$HUB_DATA/backups" \
                  "$HUB_DATA/conf" \
                  "$HUB_DATA/data" \
                  "$HUB_LOGS"
  ```

3. Set permissions.

  The Dockerfile creates a `hub` user and group. This user has a `UID` and `GID` of `4000`. Make sure to add a user to your host system with this `UID` and `GID` and allow this user to read and write to `$HUB_DATA` and `$HUB_LOGS`. The name of the host user and group in not important.

  ```sh
  # Create hub group and user in docker host, e.g.:
  groupadd --gid 4000 --system hub
  useradd --uid 4000 --gid 4000 --system --shell /sbin/nologin --comment "JetBrains Hub" hub

  # 4000 is the ID of the hub user and group created by the Dockerfile.
  chown -R 4000:4000 "$HUB_DATA" "$HUB_LOGS"
  ```

4. Create your container.

  *Note:* The `:z` option on the volume mounts makes sure the SELinux context of the directories are [set appropriately.](http://www.projectatomic.io/blog/2015/06/using-volumes-with-docker-can-cause-problems-with-selinux/)

  `/etc/localtime` needs to be bind-mounted to use the same time zone as your docker host.

  ```sh
  docker create -it -p $PORT:8080 \
                    -v /etc/localtime:/etc/localtime:ro \
                    -v "$HUB_DATA/backups:/hub/backups:z" \
                    -v "$HUB_DATA/conf:/hub/conf:z" \
                    -v "$HUB_DATA/data:/hub/data:z" \
                    -v "$HUB_LOGS:/hub/logs:z" \
                    --name hub \
                    agross/hub
  ```

5. Create systemd unit, e.g. `/etc/systemd/system/hub.service`.

  ```sh
  cat <<EOF > "/etc/systemd/system/hub.service"
  [Unit]
  Description=JetBrains Hub
  Requires=docker.service
  After=docker.service

  [Service]
  Restart=always
  # When docker stop is executed, the docker-entrypoint.sh trap + wait combination
  # will generate an exit status of 143 = 128 + 15 (SIGTERM).
  # More information: http://veithen.github.io/2014/11/16/sigterm-propagation.html
  SuccessExitStatus=143
  PrivateTmp=true
  ExecStart=/usr/bin/docker start --attach=true hub
  ExecStop=/usr/bin/docker stop --time=60 hub

  [Install]
  WantedBy=multi-user.target
  EOF

  systemctl enable hub.service
  systemctl start hub.service
  ```

6. Setup logrotate, e.g. `/etc/logrotate.d/hub`.

  ```sh
  cat <<EOF > "/etc/logrotate.d/hub"
  $HUB_LOGS/*.log
  $HUB_LOGS/dashboard/*.log
  $HUB_LOGS/hub/*.log
  $HUB_LOGS/hub/logs/*.log
  $HUB_LOGS/internal/services/bundleProcess/*.log
  $HUB_LOGS/project-wizard/*.log
  {
    rotate 7
    daily
    dateext
    missingok
    notifempty
    sharedscripts
    copytruncate
    compress
  }
  EOF
  ```
7. Add nginx configuration, e.g. `/etc/nginx/conf.d/hub.conf`.

  ```sh
  cat <<EOF > "/etc/nginx/conf.d/hub.conf"
  upstream hub {
    server localhost:$PORT;
  }

  server {
    listen           80;
    listen      [::]:80;

    server_name $DOMAIN;

    access_log  /var/log/nginx/$DOMAIN.access.log;
    error_log   /var/log/nginx/$DOMAIN.error.log;

    # Do not limit upload.
    client_max_body_size 0;

    # Required to avoid HTTP 411: see issue #1486 (https://github.com/dotcloud/docker/issues/1486)
    chunked_transfer_encoding on;

    location / {
      proxy_pass http://hub;

      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-Host \$http_host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_http_version 1.1;
    }
  }
  EOF

  nginx -s reload
  ```

  Make sure SELinux policy allows nginx to access port `$PORT` (the first part of `-p $PORT:8080` of step 3).

  ```sh
  if [ $(semanage port --list | grep --count "^http_port_t.*$PORT") -eq 0 ]; then
    if semanage port --add --type http_port_t --proto tcp $PORT; then
      echo Added port $PORT as a valid port for nginx:
      semanage port --list | grep ^http_port_t
    else
      >&2 echo Could not add port $PORT as a valid port for nginx. Please add it yourself. More information: http://axilleas.me/en/blog/2013/selinux-policy-for-nginx-and-gitlab-unix-socket-in-fedora-19/
    fi
  else
    echo Port $PORT is already a valid port for nginx:
    semanage port --list | grep ^http_port_t
  fi
  ```

8. Configure Hub.

  Follow the steps of the installation [instructions for JetBrains Hub](https://confluence.jetbrains.com/display/YTD65/Installing+Hub+with+ZIP+Distribution) using paths inside the docker container located under

  * `/hub/backups`,
  * `/hub/data`,
  * `/hub/logs` and
  * `/hub/temp`.

9. Update to a newer version.

  ```sh
  docker pull agross/hub

  systemctl stop hub.service

  # Back up $HUB_DATA.
  tar -zcvf "hub-data-$(date +%F-%H-%M-%S).tar.gz" "$HUB_DATA"

  docker rm hub

  # Repeat step 4 and create a new image.
  docker create ...

  systemctl start hub.service
  ```

## Building and testing the `Dockerfile`

1. Build the `Dockerfile`.

  ```sh
  docker build --tag agross/hub:testing .

  docker images
  # Should contain:
  # REPOSITORY                        TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
  # agross/hub                   testing             0dcb8bf6093f        49 seconds ago      405.4 MB

  ```

2. Prepare directories for testing.

  ```sh
  TEST_DIR="/tmp/hub-testing"

  mkdir --parents "$TEST_DIR/backups" \
                  "$TEST_DIR/conf" \
                  "$TEST_DIR/data" \
                  "$TEST_DIR/logs"
  chown -R 4000:4000 "$TEST_DIR"
  ```

3. Run the container built in step 1.

  *Note:* The `:z` option on the volume mounts makes sure the SELinux context of the directories are [set appropriately.](http://www.projectatomic.io/blog/2015/06/using-volumes-with-docker-can-cause-problems-with-selinux/)

  ```sh
  docker run -it --rm \
                 --name hub-testing \
                 -p 8080:8080 \
                 -v "$TEST_DIR/backups:/hub/backups:z" \
                 -v "$TEST_DIR/conf:/hub/conf:z" \
                 -v "$TEST_DIR/data:/hub/data:z" \
                 -v "$TEST_DIR/logs:/hub/logs:z" \
                 agross/hub:testing
  ```

4. Open a shell to your running container.

  ```sh
  docker exec -it hub-testing bash
  ```

5. Run bash instead of starting Hub.

  *Note:* The `:z` option on the volume mounts makes sure the SELinux context of the directories are [set appropriately.](http://www.projectatomic.io/blog/2015/06/using-volumes-with-docker-can-cause-problems-with-selinux/)

  ```sh
  docker run -it -v "$TEST_DIR/backups:/hub/backups:z" \
                 -v "$TEST_DIR/conf:/hub/conf:z" \
                 -v "$TEST_DIR/data:/hub/data:z" \
                 -v "$TEST_DIR/logs:/hub/logs:z" \
                 agross/hub:testing bash
  ```

  Without mounted data directories:

  ```sh
  docker run -it agross/hub:testing bash
  ```

6. Clean up after yourself.

  ```sh
  docker ps -aq --no-trunc --filter ancestor=agross/hub:testing | xargs --no-run-if-empty docker rm
  docker images -q --no-trunc agross/hub:testing | xargs --no-run-if-empty docker rmi
  rm -rf "$TEST_DIR"
  ```
