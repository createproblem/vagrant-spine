<?php
/**
 * If a custom dashboard file exists, load that instead of the default
 * dashboard provided by Varying Vagrant Vagrants. This file should be
 * located in the `www/default/` directory.
 */
if ( file_exists( 'dashboard-custom.php' ) ) {
	include( 'dashboard-custom.php' );
	exit;
}
// Begin default dashboard.
?>
<!DOCTYPE html>
<html>
<head>
	<title>Vagrant Spine Development Environment</title>
	<meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body>

<ul class="nav">
	<li><a href="https://github.com/createproblem/vagrant-spine">Repository</a></li>
	<li><a href="opcache-status/opcache.php">Opcache Status</a></li>
	<li><a href="phpinfo/">PHP Info</a></li>
	<li><a href="database-admin/">phpMyAdmin</a></li>
 <!--    <li><a href="http://192.168.56.105:9200/_plugin/head/">Elasticsearch Head</a></li>
    <li><a href="http://192.168.56.105:5601/app/marvel">Elasticsearch Marvel</a></li>
    <li><a href="http://192.168.56.105:5601/app/kibana">Elasticsearch Kibana</a></li>
	<li><a href="http://192.168.56.105:15672">RabbitMQ</a></li> -->
</ul>

<h2>Spinebox</h2>
<p>
	Username: ubuntu<br>
	Password: ubuntu<br>
</p>
<h2>MySQL</h2>
<p>
	Username: root<br>
	Password: root<br>
	Port: 3306
</p>
</body>
</html>
