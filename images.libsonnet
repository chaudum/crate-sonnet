{
  _images+:: {
    crate: 'crate:%s' % [$._config.version],
    busybox: 'busybox:latest',
    sql_exporter: 'githubfree/sql_exporter:latest',
  },
}
