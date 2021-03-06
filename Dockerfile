# This is a 2-stage Docker build.  In the first stage, we build a
# Zulip development environment image and use
# tools/build-release-tarball to generate a production release tarball
# from the provided Git ref.
FROM ubuntu:bionic
LABEL maintainer="Alexander Trost <galexrt@googlemail.com>"
# You can specify these in docker-compose.yml or with
#   docker build --build-args "ZULIP_GIT_REF=git_branch_name" .
ARG ZULIP_GIT_URL=https://github.com/zulip/zulip.git
ARG ZULIP_GIT_REF=master
ARG CUSTOM_CA_CERTIFICATES=
ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-xuo", "pipefail", "-c"]
# First, we setup, and generate working locales
RUN \
    echo 'APT::Install-Recommends 0;' >> /etc/apt/apt.conf.d/01norecommends && \
    echo 'APT::Install-Suggests 0;' >> /etc/apt/apt.conf.d/01norecommends && \
    apt-get -q update && \
    apt-get -q install locales && \
    locale-gen en_US.UTF-8
# Set locale, and set timezone to Etc/UTC    
ENV LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    LC_ALL="en_US.UTF-8" \
    TZ=Etc/UTC

# Next, we upgrade the base image and add a zulip user
RUN \
    apt-get -q update && \
    apt-get -q dist-upgrade -y && \
    apt-get -q install -y git sudo ca-certificates apt-transport-https python3 crudini gnupg && \
    useradd -d /home/zulip -m zulip && \
    echo 'zulip ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers
    
RUN \
    git clone "$ZULIP_GIT_URL" && \
    (cd zulip && git checkout "$ZULIP_GIT_REF") && \
    chown -R zulip:zulip zulip && \
    mv zulip /home/zulip/zulip && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apt-get -q install -y tzdata

USER zulip
WORKDIR /home/zulip/zulip
# Finally, we provision the development environment and build a release tarball
# And since were trying to also make use of same build procedure to generate release tarball and work with Docker, were unpack same tarball to save some space
RUN ./tools/provision --production-travis
RUN \
    /bin/bash -c "source /srv/zulip-py3-venv/bin/activate && ./tools/build-release-tarball docker" && \
    mv /tmp/tmp.*/zulip-server-docker.tar.gz /tmp/zulip-server-docker.tar.gz && \
    mkdir -p /home/zulip/buildzone/zulip-unarchived && \
    mv /tmp/zulip-server-docker.tar.gz /home/zulip/buildzone/zulip-server-docker.tar.gz && \
    tar xfvz /home/zulip/buildzone/zulip-server-docker.tar.gz -C /home/zulip/buildzone/zulip-unarchived/

# In the second stage, we build the production image from the unpacked release tarball

FROM ubuntu:bionic
ARG CUSTOM_CA_CERTIFICATES=
ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-xuo", "pipefail", "-c"]
# Set locales and timezone
ENV DATA_DIR="/data" \
    LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    LC_ALL="en_US.UTF-8" \
    TZ=Etc/UTC

# We setup these environments twice, probably squash them, later
ENV LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    LC_ALL="en_US.UTF-8"
ENV PUPPET_CLASSES="zulip::dockervoyager" \
    DEPLOYMENT_TYPE="dockervoyager" \
    ADDITIONAL_PACKAGES="expect"
# Copy unpacked tar from build-tarball stage
# Way to improve, and not hold them as layers -- download in second phase and do in chain before land removal/move,
# not copy from one layer to another
COPY --from=0 /home/zulip/buildzone/zulip-unarchived/zulip-server-docker/ /root/zulip-server-docker/
COPY custom_zulip_files/ /root/custom_zulip

# Then, with a second image, we install the production release tarball.
RUN \
    echo 'APT::Install-Recommends 0;' >> /etc/apt/apt.conf.d/01norecommends && \
    echo 'APT::Install-Suggests 0;' >> /etc/apt/apt.conf.d/01norecommends && \
    apt-get -q update && \
    apt-get -q install locales && \
    locale-gen en_US.UTF-8 && \
    apt-get -q dist-upgrade -y && \
    apt-get -q install -y sudo ca-certificates apt-transport-https nginx-full gnupg && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apt-get -q install -y tzdata && \
    rm /etc/init.d/nginx && \
    ln -s /bin/true /etc/init.d/nginx && \
    mkdir -p "$DATA_DIR" && \
    cd /root && \
    mv zulip-server-docker zulip && \
    cp -rf /root/custom_zulip/* /root/zulip && \
    rm -rf /root/custom_zulip && \
    /root/zulip/scripts/setup/install --hostname="$(hostname)" --email="docker-zulip" --no-init-db && \
    rm -f /etc/zulip/zulip-secrets.conf /etc/zulip/settings.py && \
    apt-get -qq autoremove --purge -y && \
    apt-get -qq clean && \
#    usermod -aG tty zulip && \
#    chmod o+w /dev/stdout && \
#    ln -sf /dev/stdout /var/log/nginx/access.log && \
#    ln -sf /dev/stderr /var/log/nginx/error.log && \
#    ln -sf /dev/stdout /var/log/zulip/analytics.log && \
#    ln -sf /dev/stdout /var/log/zulip/digest.log && \
#    ln -sf /dev/stdout /var/log/zulip/django.log && \
#    ln -sf /dev/stdout /var/log/zulip/email-deliverer.log && \
#    ln -sf /dev/stdout /var/log/zulip/errors.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_deferred_work.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_deliver_enqueued_emails.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_digest_emails.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_email_mirror.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_email_senders.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_embedded_bots.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_embed_links.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_error_reports.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_feedback_messages.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_invites.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_message_sender.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_missedmessage_email_senders.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_missedmessage_emails.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_missedmessage_mobile_notifications.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_outgoing_webhooks.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_scheduled_message_deliverer.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_signups.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_slow_queries.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_user_activity_interval.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_user_activity.log && \
#    ln -sf /dev/stdout /var/log/zulip/events_user_presence.log && \
#    ln -sf /dev/stdout /var/log/zulip/fts-updates.log && \
#    ln -sf /dev/stdout /var/log/zulip/install.log && \
#    ln -sf /dev/stdout /var/log/zulip/manage.log && \
#    ln -sf /dev/stdout /var/log/zulip/queue_error && \
#    ln -sf /dev/stdout /var/log/zulip/scheduled_message_deliverer.log && \
#    ln -sf /dev/stdout /var/log/zulip/send_email.log && \
#    ln -sf /dev/stdout /var/log/zulip/server.log && \
#    ln -sf /dev/stdout /var/log/zulip/soft_deactivation.log && \
#    ln -sf /dev/stdout /var/log/zulip/thumbor.log && \
#    ln -sf /dev/stdout /var/log/zulip/tornado.log && \
#    ln -sf /dev/stdout /var/log/zulip/webhooks_errors.log && \
#    ln -sf /dev/stdout /var/log/zulip/workers.log && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY entrypoint.sh /sbin/entrypoint.sh
COPY certbot-deploy-hook /sbin/certbot-deploy-hook

VOLUME ["$DATA_DIR"]
EXPOSE 80 443

ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["app:run"]
