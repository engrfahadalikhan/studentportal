<?php
// Copy this file to config.php on the server and fill real credentials there.
// Do not commit config.php because it contains production secrets.
return [
    'db_host' => 'localhost',
    'db_name' => 'your_database_name',
    'db_user' => 'your_database_user',
    'db_pass' => 'your_database_password',

    // Shared secret the app sends in the "X-AC-Token" header.
    'api_token' => 'change-this-token',
];
