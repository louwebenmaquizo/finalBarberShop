<?php
// Enable error reporting for debugging (disable in production)
error_reporting(E_ALL);
ini_set('display_errors', 1);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// Check if config.php exists
if (!file_exists('config.php')) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Configuration file not found',
        'error' => 'config.php is missing. Please create it with database credentials.'
    ]);
    exit();
}

require_once 'config.php';

// Check if database constants are defined
if (!defined('DB_HOST') || !defined('DB_USER') || !defined('DB_PASS') || !defined('DB_NAME')) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Database configuration incomplete',
        'error' => 'config.php must define DB_HOST, DB_USER, DB_PASS, and DB_NAME'
    ]);
    exit();
}

try {
    $conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
    
    if ($conn->connect_error) {
        throw new Exception("Connection failed: " . $conn->connect_error);
    }
    
    // Handle GET requests for checking if feedback exists
    if ($_SERVER['REQUEST_METHOD'] === 'GET') {
        // Get query parameters
        $appointmentId = isset($_GET['appointment_id']) ? $conn->real_escape_string(trim($_GET['appointment_id'])) : '';
        $customerId = isset($_GET['customer_id']) ? $conn->real_escape_string(trim($_GET['customer_id'])) : '';
        
        if (empty($appointmentId) || empty($customerId)) {
            throw new Exception("Appointment ID and Customer ID are required");
        }
        
        // Check if feedback exists
        $checkSql = "SELECT feedback_id, rating, comments, created_at 
                     FROM feedback 
                     WHERE appointment_id = '$appointmentId' AND customer_id = '$customerId' 
                     LIMIT 1";
        $result = $conn->query($checkSql);
        
        if ($result && $result->num_rows > 0) {
            $feedback = $result->fetch_assoc();
            echo json_encode([
                'success' => true,
                'data' => $feedback,
                'has_feedback' => true
            ]);
        } else {
            echo json_encode([
                'success' => true,
                'data' => null,
                'has_feedback' => false
            ]);
        }
    }
    // Handle POST requests for submitting feedback
    else if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        // Get JSON data from request body
        $rawInput = file_get_contents('php://input');
        $data = json_decode($rawInput, true);
        
        if (!$data) {
            $jsonError = json_last_error_msg();
            throw new Exception("Invalid JSON data: " . $jsonError);
        }
        
        // Validate required fields
        if (empty($data['appointment_id'])) {
            throw new Exception("Appointment ID is required");
        }
        if (empty($data['customer_id'])) {
            throw new Exception("Customer ID is required");
        }
        if (!isset($data['rating']) || !is_numeric($data['rating'])) {
            throw new Exception("Rating is required and must be a number");
        }
        
        $rating = intval($data['rating']);
        
        // Validate rating range (1-5)
        if ($rating < 1 || $rating > 5) {
            throw new Exception("Rating must be between 1 and 5");
        }
        
        // Escape and prepare data
        $appointmentId = $conn->real_escape_string(trim($data['appointment_id']));
        $customerId = $conn->real_escape_string(trim($data['customer_id']));
        $comments = isset($data['comments']) && !empty($data['comments'])
            ? $conn->real_escape_string(trim($data['comments']))
            : null;
        
        // Check if feedback already exists for this appointment
        $checkSql = "SELECT feedback_id FROM feedback WHERE appointment_id = '$appointmentId' AND customer_id = '$customerId'";
        $checkResult = $conn->query($checkSql);
        
        if ($checkResult && $checkResult->num_rows > 0) {
            // Update existing feedback
            $updateSql = "UPDATE feedback SET rating = $rating";
            if ($comments !== null) {
                $updateSql .= ", comments = '$comments'";
            }
            $updateSql .= " WHERE appointment_id = '$appointmentId' AND customer_id = '$customerId'";
            
            if (!$conn->query($updateSql)) {
                throw new Exception("Failed to update feedback: " . $conn->error);
            }
            
            echo json_encode([
                'success' => true,
                'message' => 'Feedback updated successfully',
                'data' => [
                    'appointment_id' => $appointmentId,
                    'customer_id' => $customerId,
                    'rating' => $rating,
                ]
            ]);
        } else {
            // Insert new feedback
            $insertSql = "INSERT INTO feedback (appointment_id, customer_id, rating";
            $valuesSql = "VALUES ('$appointmentId', '$customerId', $rating";
            
            if ($comments !== null) {
                $insertSql .= ", comments";
                $valuesSql .= ", '$comments'";
            }
            
            $insertSql .= ") " . $valuesSql . ")";
            
            if (!$conn->query($insertSql)) {
                throw new Exception("Failed to create feedback: " . $conn->error);
            }
            
            $feedbackId = $conn->insert_id;
            
            echo json_encode([
                'success' => true,
                'message' => 'Feedback submitted successfully',
                'data' => [
                    'feedback_id' => $feedbackId,
                    'appointment_id' => $appointmentId,
                    'customer_id' => $customerId,
                    'rating' => $rating,
                ]
            ]);
        }
    } else {
        throw new Exception("Only POST method is allowed");
    }
    
    $conn->close();
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage(),
        'error' => $e->getMessage()
    ]);
}
?>

