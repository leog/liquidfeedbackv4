FROM nickblah/lua:5.3
SHELL ["/bin/bash", "-c"]
# Use baseimage-docker's init system.
#RUN /sbin/my_init

# 1. Install necessary dependencies
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get install -y build-essential wget apt-utils lsb-release vim
RUN apt-get install -y liblua5.3-dev
RUN apt-get install -y postgresql libpq-dev
RUN apt-get install -y pmake
RUN apt-get install -y imagemagick sassc
RUN apt-get install -y exim4
RUN apt-get install -y python3-markdown2

RUN apt-get install -y postgresql-server-dev-*
RUN cp -rf /usr/include/postgresql/* /usr/include
RUN cp -rf /usr/include/postgresql/*/server/* /usr/include

# Components version
ENV LF_CORE_VERSION 4.2.2
ENV MOONBRIDGE_VERSION 1.1.3
ENV WEBMCP_VERSION 2.2.1
ENV PGLATLON_VERSION 0.15

# 1a. Install pgLatLon dependency (only for LiquidFeedback Core v4 or higher)
USER root
RUN cd /
RUN wget -c https://www.public-software-group.org/pub/projects/pgLatLon/v${PGLATLON_VERSION}/pgLatLon-v${PGLATLON_VERSION}.tar.gz
RUN tar xzvf pgLatLon-v${PGLATLON_VERSION}.tar.gz
RUN cd pgLatLon-v${PGLATLON_VERSION} && make install

# 2. Ensure that the user account of your web server has access to the database
USER postgres
RUN /etc/init.d/postgresql start && \
	createuser --superuser --createdb --no-createrole www-data

# 3. Install and configure LiquidFeedback-Core
USER root
RUN cd /
RUN wget -c http://www.public-software-group.org/pub/projects/liquid_feedback/backend/v${LF_CORE_VERSION}/liquid_feedback_core-v${LF_CORE_VERSION}.tar.gz
RUN tar xzvf liquid_feedback_core-v${LF_CORE_VERSION}.tar.gz
RUN cd liquid_feedback_core-v${LF_CORE_VERSION} && make
RUN mkdir -p /opt/liquid_feedback_core
RUN cd /liquid_feedback_core-v${LF_CORE_VERSION} && \
	cp -f core.sql test.sql lf_update lf_update_issue_order lf_update_suggestion_order /opt/liquid_feedback_core
RUN echo "INSERT INTO member (invite_code, admin) VALUES ('sesam', true);" >> /opt/liquid_feedback_core/test.sql

COPY createdb.sql /tmp
RUN cd /opt/liquid_feedback_core
RUN /etc/init.d/postgresql start && \
	su - www-data -s /bin/sh -c 'createdb liquid_feedback' && \
	su - www-data -s /bin/sh -c '/usr/bin/psql -v ON_ERROR_STOP=1 -f /opt/liquid_feedback_core/core.sql liquid_feedback' && \
	su - www-data -s /bin/sh -c '/usr/bin/psql -v ON_ERROR_STOP=1 -f /opt/liquid_feedback_core/test.sql liquid_feedback' && \
	su - www-data -s /bin/sh -c '/usr/bin/psql -f /tmp/createdb.sql liquid_feedback'

# 4. Install Moonbridge
USER root
RUN cd /
RUN wget -c http://www.public-software-group.org/pub/projects/moonbridge/v${MOONBRIDGE_VERSION}/moonbridge-v${MOONBRIDGE_VERSION}.tar.gz
RUN tar xzvf moonbridge-v${MOONBRIDGE_VERSION}.tar.gz
RUN apt-get install -y libbsd-dev
RUN mkdir -p /opt/moonbridge
RUN cd moonbridge-v${MOONBRIDGE_VERSION} ; \
	pmake MOONBR_LUA_PATH=/opt/moonbridge/?.lua && \
	cp -f moonbridge /opt/moonbridge/ && \
	cp -f moonbridge_http.lua /opt/moonbridge/

# 5. Install WebMCP
USER root
RUN cd /
RUN wget -c http://www.public-software-group.org/pub/projects/webmcp/v${WEBMCP_VERSION}/webmcp-v${WEBMCP_VERSION}.tar.gz
RUN tar xzvf webmcp-v${WEBMCP_VERSION}.tar.gz
RUN mkdir -p /opt/webmcp
RUN cd webmcp-v${WEBMCP_VERSION} && make && \
	cp -RL framework/* /opt/webmcp/ && \
	cp -RL libraries/* /opt/webmcp/lib

# 6. Install the LiquidFeedback-Frontend
USER root
RUN cd /
RUN apt-get install -y git
RUN git clone https://github.com/fluidemocracy/frontend-legacy.git /opt/liquid_feedback_frontend
RUN mkdir -p /opt/liquid_feedback_frontend/tmp && \
	chown -R www-data /opt/liquid_feedback_frontend/tmp

# 7. Configure mail system
RUN echo exim4-config exim4/dc_eximconfig_configtype select "internet site; mail is sent and received directly using SMTP" | debconf-set-selections && \
	echo exim4-config exim4/use_split_config boolean true | debconf-set-selections && \
	echo exim4-config exim4/mailname string "2buntu.com" | debconf-set-selections
RUN DEBIAN_FRONTEND=noninteractive dpkg-reconfigure exim4-config

# 8. Configure the LiquidFeedback-Frontend
RUN echo $'config.instance_name = "Instance name" \n\
	config.app_service_provider = "Snake Oil<br/>10000 Berlin<br/>Germany" \n\
	config.use_terms = "<h1>Terms of Use</h1><p>Insert terms here</p>" \n\
	config.absolute_base_url = "http://localhost:8080/lf/" \n\
	config.database = { engine="postgresql", dbname="liquid_feedback" } \n\
	config.enforce_formatting_engine = "markdown2" \n\
	config.formatting_engines = { \n\
	{ id = "markdown2", \n\
	name = "python-markdown2", \n\
	executable = "markdown2", \n\
	args = {"-s", "escape", "-x", "nofollow,wiki-tables"}, \n\
	remove_images = true \n\
	}, \n\
	} \n\
	config.public_access = "anonymous" \n\
	config.enabled_languages = { "en" } \n\
	config.default_lang = "en" \n\
	config.localhost = false \n\
	config.port = 8080 \n\
	config.enable_debug_trace = true \n\
	' > /opt/liquid_feedback_frontend/config/myconfig.lua

# 9. Setup regular execution of lf_update and related commands
COPY lf_updated /opt/liquid_feedback_core/lf_updated
RUN chmod +x /opt/liquid_feedback_core/lf_updated 

# 10. Start the system
CMD	echo "Starting LiquidFeedback..." ; \
	/etc/init.d/postgresql start ; \
	su - www-data -s /bin/sh -c "/opt/moonbridge/moonbridge --debug /opt/webmcp/bin/mcp.lua /opt/webmcp/ /opt/liquid_feedback_frontend/ main myconfig" ; \
	/opt/liquid_feedback_core/lf_updated

# Cleaning up
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
RUN rm -rf /usr/include /usr/share/man /usr/share/doc