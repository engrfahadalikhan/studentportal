<?php
// AUST Connect — single-file REST API (complaints + file tracking).
// Endpoint: https://aust.live/aust_connect/api.php?action=<action>
// Auth: header  X-AC-Token: <api_token from config.php>
// Body: JSON (POST) for writes; query params for reads.

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, X-AC-Token');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }

$cfg = require __DIR__ . '/config.php';

function out($ok, $data = [], $code = 200) {
    http_response_code($code);
    echo json_encode(array_merge(['ok' => $ok], $data));
    exit;
}

// --- auth ---
$token = $_SERVER['HTTP_X_AC_TOKEN'] ?? '';
if (!hash_equals($cfg['api_token'], $token)) {
    out(false, ['error' => 'Bad or missing X-AC-Token.'], 401);
}

// --- db ---
try {
    $pdo = new PDO(
        "mysql:host={$cfg['db_host']};dbname={$cfg['db_name']};charset=utf8mb4",
        $cfg['db_user'], $cfg['db_pass'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
         PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
    );
} catch (Throwable $e) {
    out(false, ['error' => 'DB connect failed: ' . $e->getMessage()], 500);
}

// --- schema (idempotent) ---
$pdo->exec("CREATE TABLE IF NOT EXISTS ac_departments(
    id VARCHAR(40) PRIMARY KEY, name VARCHAR(160) NOT NULL, seq INT NOT NULL DEFAULT 0,
    staff TEXT NULL, updated_at VARCHAR(40) NOT NULL, deleted TINYINT NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
$pdo->exec("CREATE TABLE IF NOT EXISTS ac_complaints(
    id VARCHAR(40) PRIMARY KEY, tracking_id VARCHAR(24) NOT NULL,
    category VARCHAR(80) NOT NULL DEFAULT '', subject VARCHAR(200) NOT NULL DEFAULT '',
    body TEXT NOT NULL, by_name VARCHAR(160) NOT NULL DEFAULT '',
    by_role VARCHAR(20) NOT NULL DEFAULT '', by_id VARCHAR(80) NOT NULL DEFAULT '',
    is_anon TINYINT NOT NULL DEFAULT 1, status VARCHAR(20) NOT NULL DEFAULT 'new',
    handled_by VARCHAR(160) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL, updated_at VARCHAR(40) NOT NULL,
    done_at VARCHAR(40) NULL, deleted TINYINT NOT NULL DEFAULT 0,
    INDEX(updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
$pdo->exec("CREATE TABLE IF NOT EXISTS ac_files(
    id VARCHAR(40) PRIMARY KEY, tracking_id VARCHAR(24) NOT NULL,
    title VARCHAR(200) NOT NULL DEFAULT '', description TEXT NULL,
    by_name VARCHAR(160) NOT NULL DEFAULT '', by_role VARCHAR(20) NOT NULL DEFAULT '',
    by_id VARCHAR(80) NOT NULL DEFAULT '', current_seq INT NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'submitted', steps_json MEDIUMTEXT NOT NULL,
    created_at VARCHAR(40) NOT NULL, updated_at VARCHAR(40) NOT NULL,
    completed_at VARCHAR(40) NULL, deleted TINYINT NOT NULL DEFAULT 0,
    INDEX(updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
$pdo->exec("CREATE TABLE IF NOT EXISTS ac_notifications(
    id VARCHAR(40) PRIMARY KEY, user_key VARCHAR(120) NOT NULL,
    title VARCHAR(200) NOT NULL DEFAULT '', body TEXT NULL,
    ref_type VARCHAR(20) NOT NULL DEFAULT '', ref_id VARCHAR(40) NOT NULL DEFAULT '',
    created_at VARCHAR(40) NOT NULL, read_at VARCHAR(40) NULL,
    INDEX(user_key), INDEX(created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$action = $_GET['action'] ?? '';
$body = json_decode(file_get_contents('php://input'), true) ?: [];
function b($body, $k, $d = '') { return isset($body[$k]) ? $body[$k] : $d; }
function nowIso() { return gmdate('Y-m-d\TH:i:s.v\Z'); }
function nid($p) { return $p . bin2hex(random_bytes(8)); }
function track($p) { return $p . strtoupper(substr(bin2hex(random_bytes(3)), 0, 5)); }

switch ($action) {

case 'ping':
    out(true, ['time' => nowIso()]);

// ---- PULL everything changed since ?since= (shared dashboard) ----
case 'pull':
    $since = $_GET['since'] ?? '';
    $q = function($sql) use ($pdo, $since) {
        $st = $pdo->prepare($sql);
        $st->execute([$since]);
        return $st->fetchAll();
    };
    out(true, [
        'time' => nowIso(),
        'departments' => $q("SELECT * FROM ac_departments WHERE updated_at > ? ORDER BY seq"),
        'complaints'  => $q("SELECT * FROM ac_complaints WHERE updated_at > ? ORDER BY updated_at"),
        'files'       => $q("SELECT * FROM ac_files WHERE updated_at > ? ORDER BY updated_at"),
    ]);

case 'notifications':
    $uk = $_GET['user'] ?? '';
    $st = $pdo->prepare("SELECT * FROM ac_notifications WHERE user_key = ? ORDER BY created_at DESC LIMIT 200");
    $st->execute([$uk]);
    out(true, ['notifications' => $st->fetchAll()]);

// ---- COMPLAINTS ----
case 'submit_complaint':
    $id = nid('C'); $now = nowIso(); $tid = track('CMP-');
    $st = $pdo->prepare("INSERT INTO ac_complaints
        (id,tracking_id,category,subject,body,by_name,by_role,by_id,is_anon,status,created_at,updated_at)
        VALUES (?,?,?,?,?,?,?,?,?, 'new', ?, ?)");
    $st->execute([$id,$tid,b($body,'category'),b($body,'subject'),b($body,'body'),
        b($body,'by_name'),b($body,'by_role'),b($body,'by_id'),
        b($body,'is_anon',1) ? 1 : 0, $now, $now]);
    out(true, ['id' => $id, 'tracking_id' => $tid]);

case 'set_complaint_status':
    $id = b($body,'id'); $status = b($body,'status'); $now = nowIso();
    $done = $status === 'done' ? $now : null;
    $st = $pdo->prepare("UPDATE ac_complaints SET status=?, handled_by=?, updated_at=?,
        done_at=CASE WHEN ?='done' THEN ? ELSE done_at END WHERE id=?");
    $st->execute([$status, b($body,'handled_by'), $now, $status, $done, $id]);
    // notify the submitter
    $c = $pdo->prepare("SELECT tracking_id, by_id, is_anon FROM ac_complaints WHERE id=?");
    $c->execute([$id]); $row = $c->fetch();
    if ($row && $row['by_id']) {
        $n = $pdo->prepare("INSERT INTO ac_notifications (id,user_key,title,body,ref_type,ref_id,created_at)
            VALUES (?,?,?,?, 'complaint', ?, ?)");
        $n->execute([nid('N'), $row['by_id'], 'Complaint '.$row['tracking_id'],
            'Status changed to '.strtoupper($status), $id, $now]);
    }
    out(true, ['updated_at' => $now]);

case 'delete_complaint':
    $st = $pdo->prepare("UPDATE ac_complaints SET deleted=1, updated_at=? WHERE id=?");
    $st->execute([nowIso(), b($body,'id')]);
    out(true);

// ---- DEPARTMENTS ----
case 'upsert_department':
    $id = b($body,'id'); if (!$id) $id = nid('D'); $now = nowIso();
    $st = $pdo->prepare("INSERT INTO ac_departments (id,name,seq,staff,updated_at,deleted)
        VALUES (?,?,?,?,?,0)
        ON DUPLICATE KEY UPDATE name=VALUES(name), seq=VALUES(seq), staff=VALUES(staff),
        updated_at=VALUES(updated_at), deleted=0");
    $st->execute([$id, b($body,'name'), (int)b($body,'seq',0),
        json_encode(b($body,'staff',[])), $now]);
    out(true, ['id' => $id]);

case 'delete_department':
    $st = $pdo->prepare("UPDATE ac_departments SET deleted=1, updated_at=? WHERE id=?");
    $st->execute([nowIso(), b($body,'id')]);
    out(true);

// ---- FILE TRACKING ----
case 'submit_file':
    $id = nid('F'); $now = nowIso(); $tid = track('FILE-');
    $steps = b($body,'steps',[]); // [{dept_id,dept_name,seq}]
    // step statuses: pending / under_process / done
    foreach ($steps as &$s2) { $s2['status'] = 'pending'; $s2['note']=''; $s2['by']=''; $s2['at']=''; }
    unset($s2);
    $st = $pdo->prepare("INSERT INTO ac_files
        (id,tracking_id,title,description,by_name,by_role,by_id,current_seq,status,steps_json,created_at,updated_at)
        VALUES (?,?,?,?,?,?,?, 0, 'submitted', ?, ?, ?)");
    $st->execute([$id,$tid,b($body,'title'),b($body,'description'),
        b($body,'by_name'),b($body,'by_role'),b($body,'by_id'),
        json_encode($steps), $now, $now]);
    out(true, ['id' => $id, 'tracking_id' => $tid]);

case 'advance_file':
    $id = b($body,'id'); $stepStatus = b($body,'step_status'); // under_process|done
    $by = b($body,'by'); $now = nowIso();
    $c = $pdo->prepare("SELECT * FROM ac_files WHERE id=?"); $c->execute([$id]);
    $f = $c->fetch();
    if (!$f) out(false, ['error' => 'File not found'], 404);
    $steps = json_decode($f['steps_json'], true) ?: [];
    $cur = (int)$f['current_seq'];
    $status = $f['status'];
    for ($i = 0; $i < count($steps); $i++) {
        if ((int)$steps[$i]['seq'] === $cur) {
            $steps[$i]['status'] = $stepStatus;
            $steps[$i]['by'] = $by; $steps[$i]['at'] = $now;
            if ($stepStatus === 'done') {
                if ($i + 1 < count($steps)) { $cur = (int)$steps[$i+1]['seq']; $status = 'in_progress'; }
                else { $status = 'completed'; }
            } else { $status = 'in_progress'; }
            break;
        }
    }
    $completed = $status === 'completed' ? $now : null;
    $u = $pdo->prepare("UPDATE ac_files SET steps_json=?, current_seq=?, status=?, updated_at=?,
        completed_at=CASE WHEN ?='completed' THEN ? ELSE completed_at END WHERE id=?");
    $u->execute([json_encode($steps), $cur, $status, $now, $status, $completed, $id]);
    if ($f['by_id']) {
        $curName = '';
        foreach ($steps as $s3) { if ((int)$s3['seq'] === $cur) { $curName = $s3['dept_name']; break; } }
        $msg = $status === 'completed' ? 'Your file is COMPLETED.'
             : 'Now at '.$curName.' ('.strtoupper($stepStatus).')';
        $n = $pdo->prepare("INSERT INTO ac_notifications (id,user_key,title,body,ref_type,ref_id,created_at)
            VALUES (?,?,?,?, 'file', ?, ?)");
        $n->execute([nid('N'), $f['by_id'], 'File '.$f['tracking_id'], $msg, $id, $now]);
    }
    out(true, ['status' => $status]);

case 'mark_notification_read':
    $st = $pdo->prepare("UPDATE ac_notifications SET read_at=? WHERE id=?");
    $st->execute([nowIso(), b($body,'id')]);
    out(true);

default:
    out(false, ['error' => 'Unknown action: ' . $action], 400);
}
