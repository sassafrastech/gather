# Be sure to restart your server when you modify this file.

Rails.application.config.session_store :cookie_store,
  key: '_gather_session',
  domain: Settings.url.host_without_port
