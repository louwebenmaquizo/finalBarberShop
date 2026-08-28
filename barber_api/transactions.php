<?php
/**
 * Transactions API
 * Handles payment transactions for completed appointments
 */

// Start output buffering to catch any stray output
ob_start();

// Suppress error display to prevent HTML output in JSON response
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

// Set headers before any output
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

// Handle preflight request
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// Check if config.php exists
if (!file_exists('config.php')) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'config.php is missing. Please create it with database credentials.'
    ]);
    exit();
}

require_once 'config.php';

// Check if config exists and database constants are defined
if (!defined('DB_HOST') || !defined('DB_USER') || !defined('DB_PASS') || !defined('DB_NAME')) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'config.php must define DB_HOST, DB_USER, DB_PASS, and DB_NAME'
    ]);
    exit();
}

// Database connection
$conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);

if ($conn->connect_error) {
    ob_clean(); // Clear any output
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Database connection failed: ' . $conn->connect_error
    ]);
    ob_end_flush();
    exit();
}

$method = $_SERVER['REQUEST_METHOD'];

try {
    // Clear any output before processing
    ob_clean();
    
    switch ($method) {
        case 'GET':
            handleGet($conn);
            break;
        case 'POST':
            handlePost($conn);
            break;
        case 'PUT':
            handlePut($conn);
            break;
        case 'DELETE':
            handleDelete($conn);
            break;
        default:
            ob_clean();
            http_response_code(405);
            echo json_encode([
                'success' => false,
                'error' => 'Method not allowed'
            ]);
    }
} catch (Throwable $e) {
    // Catch both Exception and Error (fatal errors)
    ob_clean();
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Server error: ' . $e->getMessage(),
        'file' => $e->getFile(),
        'line' => $e->getLine()
    ]);
} finally {
    if (isset($conn)) {
        $conn->close();
    }
    // End output buffering and send output only if there's content
    if (ob_get_length() > 0) {
        ob_end_flush();
    } else {
        // If no output was generated, send an error
        ob_clean();
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'No response generated from server'
        ]);
        ob_end_flush();
    }
}

/**
 * Handle GET request - Retrieve transactions
 */
function handleGet($conn) {
    $appointmentId = $_GET['appointment_id'] ?? null;
    $customerId = $_GET['customer_id'] ?? null;
    $staffId = $_GET['staff_id'] ?? null;
    $startDate = $_GET['start_date'] ?? null;
    $endDate = $_GET['end_date'] ?? null;

    $query = "SELECT t.*, 
                     c.full_name as customer_name,
                     s.name as staff_name
              FROM transactions t
              LEFT JOIN customers c ON t.customer_id = c.customer_id
              LEFT JOIN staff s ON t.staff_id = s.staff_id
              WHERE 1=1";
    
    $params = [];
    $types = '';

    if ($appointmentId) {
        $query .= " AND t.appointment_id = ?";
        $params[] = $appointmentId;
        $types .= 's';
    }

    if ($customerId) {
        $query .= " AND t.customer_id = ?";
        $params[] = $customerId;
        $types .= 's';
    }

    if ($staffId) {
        $query .= " AND t.staff_id = ?";
        $params[] = $staffId;
        $types .= 's';
    }

    if ($startDate) {
        $query .= " AND DATE(t.created_at) >= ?";
        $params[] = $startDate;
        $types .= 's';
    }

    if ($endDate) {
        $query .= " AND DATE(t.created_at) <= ?";
        $params[] = $endDate;
        $types .= 's';
    }

    $query .= " ORDER BY t.created_at DESC";

    $stmt = $conn->prepare($query);
    
    if (!empty($params)) {
        $stmt->bind_param($types, ...$params);
    }
    
    $stmt->execute();
    $result = $stmt->get_result();

    $transactions = [];
    while ($row = $result->fetch_assoc()) {
        // Convert numeric strings to floats for amount, tip, tax
        $row['amount'] = floatval($row['amount']);
        $row['tip_amount'] = floatval($row['tip_amount']);
        $row['tax_amount'] = floatval($row['tax_amount']);
        $transactions[] = $row;
    }

    $stmt->close();

    // If appointment_id was specified and we expect a single result
    if ($appointmentId && count($transactions) === 1) {
        echo json_encode([
            'success' => true,
            'data' => $transactions[0]
        ]);
    } else {
        echo json_encode([
            'success' => true,
            'data' => $transactions
        ]);
    }
}

/**
 * Handle POST request - Create new transaction
 */
function handlePost($conn) {
    ob_clean(); // Clear any output before sending JSON
    
    // Get JSON input
    $input = file_get_contents('php://input');
    if (empty($input)) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'No data provided'
        ]);
        return;
    }
    
    $data = json_decode($input, true);
    
    // Check if JSON decode failed
    if (json_last_error() !== JSON_ERROR_NONE) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Invalid JSON: ' . json_last_error_msg()
        ]);
        return;
    }

    // Required fields validation
    $required = ['appointment_id', 'customer_id', 'amount', 'payment_method', 'staff_id'];
    foreach ($required as $field) {
        if (!isset($data[$field]) || empty($data[$field])) {
            http_response_code(400);
            echo json_encode([
                'success' => false,
                'error' => "Missing required field: $field"
            ]);
            return;
        }
    }

    // Clean and validate payment method - ensure exact match with database constraint
    $validPaymentMethods = ['cash', 'card', 'mobile'];
    $paymentMethodInput = isset($data['payment_method']) ? trim(strtolower((string)$data['payment_method'])) : '';
    
    // Find matching valid payment method
    $paymentMethodIndex = array_search($paymentMethodInput, $validPaymentMethods);
    
    if ($paymentMethodIndex === false) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Invalid payment method. Must be: cash, card, or mobile. Received: "' . ($data['payment_method'] ?? 'NULL') . '"'
        ]);
        return;
    }
    
    // Use the exact value from the valid array (ensures no encoding/whitespace issues)
    // Explicitly cast to string to prevent any type coercion issues
    $paymentMethod = (string)$validPaymentMethods[$paymentMethodIndex];
    
    // Double-check it's a valid string value
    if (!is_string($paymentMethod) || empty($paymentMethod)) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Payment method value is invalid after processing'
        ]);
        return;
    }

    // Clean and validate status
    $statusRaw = isset($data['status']) ? trim(strtolower($data['status'])) : 'completed';
    $validStatuses = ['pending', 'completed', 'refunded', 'failed'];
    if (!in_array($statusRaw, $validStatuses)) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Invalid status. Must be: pending, completed, refunded, or failed'
        ]);
        return;
    }
    $status = $statusRaw; // Use cleaned value

    // Prepare values (no escaping needed with prepared statements)
    $appointmentId = $data['appointment_id'];
    $customerId = $data['customer_id'];
    $amount = floatval($data['amount']);
    $staffId = $data['staff_id'];
    $tipAmount = isset($data['tip_amount']) ? floatval($data['tip_amount']) : 0.0;
    $taxAmount = isset($data['tax_amount']) ? floatval($data['tax_amount']) : 0.0;


    // Validate amount
    if ($amount <= 0) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Amount must be greater than 0'
        ]);
        return;
    }

    // Check if transaction already exists for this appointment
    $checkStmt = $conn->prepare("SELECT transaction_id FROM transactions WHERE appointment_id = ?");
    $checkStmt->bind_param('s', $appointmentId);
    $checkStmt->execute();
    $checkResult = $checkStmt->get_result();
    
    if ($checkResult->num_rows > 0) {
        $checkStmt->close();
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Transaction already exists for this appointment'
        ]);
        return;
    }
    $checkStmt->close();

    // Generate transaction ID (e.g., TRAN0001)
    try {
        $transactionId = generateTransactionId($conn);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Failed to generate transaction ID: ' . $e->getMessage()
        ]);
        return;
    }

    // Insert transaction
    try {
        $stmt = $conn->prepare("INSERT INTO transactions (
            transaction_id, appointment_id, customer_id, amount, payment_method,
            tip_amount, tax_amount, staff_id, status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");

        if (!$stmt) {
            http_response_code(500);
            echo json_encode([
                'success' => false,
                'error' => 'Failed to prepare statement: ' . $conn->error
            ]);
            return;
        }

        // Log values before binding for debugging
        error_log("About to insert transaction:");
        error_log("  payment_method: '$paymentMethod' (length: " . strlen($paymentMethod) . ", type: " . gettype($paymentMethod) . ", value: " . var_export($paymentMethod, true) . ")");
        error_log("  status: '$status' (length: " . strlen($status) . ")");
        error_log("  amount: $amount");
        
        // Verify payment_method is exactly one of the valid values and is a string
        if (!is_string($paymentMethod) || !in_array($paymentMethod, ['cash', 'card', 'mobile'], true)) {
            http_response_code(500);
            echo json_encode([
                'success' => false,
                'error' => 'Payment method validation failed before insert: ' . var_export($paymentMethod, true)
            ]);
            return;
        }
        
        // Ensure all string parameters are explicitly strings
        $transactionId = (string)$transactionId;
        $appointmentId = (string)$appointmentId;
        $customerId = (string)$customerId;
        $staffId = (string)$staffId;
        $paymentMethod = (string)$paymentMethod; // Explicit cast
        $status = (string)$status; // Explicit cast
        
        $stmt->bind_param(
            'sssdsddss',
            $transactionId,
            $appointmentId,
            $customerId,
            $amount,
            $paymentMethod,
            $tipAmount,
            $taxAmount,
            $staffId,
            $status
        );

        if ($stmt->execute()) {
            echo json_encode([
                'success' => true,
                'message' => 'Transaction created successfully',
                'data' => [
                    'transaction_id' => $transactionId,
                    'appointment_id' => $appointmentId,
                    'customer_id' => $customerId,
                    'amount' => $amount,
                    'payment_method' => $paymentMethod,
                    'tip_amount' => $tipAmount,
                    'tax_amount' => $taxAmount,
                    'staff_id' => $staffId,
                    'status' => $status
                ]
            ]);
        } else {
            $errorMsg = $stmt->error;
            $connError = $conn->error;
            
            // Log detailed error information
            error_log("Transaction insert failed:");
            error_log("  Statement error: $errorMsg");
            error_log("  Connection error: $connError");
            error_log("  Payment method used: '$paymentMethod'");
            error_log("  Status used: '$status'");
            
            http_response_code(500);
            echo json_encode([
                'success' => false,
                'error' => 'Failed to create transaction: ' . $errorMsg,
                'sql_error' => $connError,
                'debug' => [
                    'payment_method' => $paymentMethod,
                    'payment_method_type' => gettype($paymentMethod),
                    'payment_method_length' => strlen($paymentMethod),
                    'payment_method_bytes' => bin2hex($paymentMethod),
                    'payment_method_ord' => array_map('ord', str_split($paymentMethod)),
                    'status' => $status,
                    'status_length' => strlen($status)
                ]
            ]);
        }

        $stmt->close();
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Database error: ' . $e->getMessage()
        ]);
    }
}

/**
 * Handle PUT request - Update transaction
 */
function handlePut($conn) {
    ob_clean(); // Clear any output before sending JSON
    $data = json_decode(file_get_contents('php://input'), true);

    if (!isset($data['transaction_id'])) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Missing transaction_id'
        ]);
        return;
    }

    $transactionId = $conn->real_escape_string($data['transaction_id']);
    $updates = [];
    $params = [];
    $types = '';

    if (isset($data['status'])) {
        $status = $conn->real_escape_string($data['status']);
        $validStatuses = ['pending', 'completed', 'refunded', 'failed'];
        if (!in_array($status, $validStatuses)) {
            http_response_code(400);
            echo json_encode([
                'success' => false,
                'error' => 'Invalid status'
            ]);
            return;
        }
        $updates[] = "status = ?";
        $params[] = $status;
        $types .= 's';
    }

    if (empty($updates)) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'No fields to update'
        ]);
        return;
    }

    $query = "UPDATE transactions SET " . implode(', ', $updates) . " WHERE transaction_id = ?";
    $params[] = $transactionId;
    $types .= 's';

    $stmt = $conn->prepare($query);
    $stmt->bind_param($types, ...$params);

    if ($stmt->execute()) {
        echo json_encode([
            'success' => true,
            'message' => 'Transaction updated successfully'
        ]);
    } else {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Failed to update transaction: ' . $stmt->error
        ]);
    }

    $stmt->close();
}

/**
 * Handle DELETE request - Delete transaction (set status to refunded)
 */
function handleDelete($conn) {
    ob_clean(); // Clear any output before sending JSON
    $transactionId = $_GET['transaction_id'] ?? null;

    if (!$transactionId) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Missing transaction_id'
        ]);
        return;
    }

    $transactionId = $conn->real_escape_string($transactionId);

    // Instead of deleting, set status to refunded
    $stmt = $conn->prepare("UPDATE transactions SET status = 'refunded' WHERE transaction_id = ?");
    $stmt->bind_param('s', $transactionId);

    if ($stmt->execute()) {
        echo json_encode([
            'success' => true,
            'message' => 'Transaction refunded successfully'
        ]);
    } else {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Failed to refund transaction: ' . $stmt->error
        ]);
    }

    $stmt->close();
}

/**
 * Generate unique transaction ID (TRAN0001, TRAN0002, etc.)
 */
function generateTransactionId($conn) {
    // Get the highest transaction number
    $result = $conn->query("SELECT transaction_id FROM transactions WHERE transaction_id LIKE 'TRAN%' ORDER BY transaction_id DESC LIMIT 1");
    
    if ($result && $result->num_rows > 0) {
        $row = $result->fetch_assoc();
        $lastId = $row['transaction_id'];
        // Extract number part (TRAN0001 -> 1)
        $number = intval(substr($lastId, 4));
        $number++;
    } else {
        $number = 1;
    }
    
    // Format as TRAN0001, TRAN0002, etc.
    return sprintf('TRAN%04d', $number);
}

