<?php
// This PHP/MySQL backend is retained only as migration reference.
// The Flutter application now uses Supabase exclusively.
header('Content-Type: application/json');
http_response_code(410);
echo json_encode([
    'success' => false,
    'error' => 'Legacy API disabled. Use the Supabase backend.'
]);
exit();

// Database Configuration
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// Database connection settings
define('DB_HOST', 'localhost');
define('DB_USER', 'root');
define('DB_PASS', '');
define('DB_NAME', 'barber');

/*
-- Database Schema:
CREATE DATABASE IF NOT EXISTS `barber`;
USE `barber`;

-- 1. Users Table
CREATE TABLE `users` (
  `user_id` char(36) NOT NULL DEFAULT uuid(),
  `username` varchar(50) NOT NULL UNIQUE,
  `email` varchar(100) NOT NULL UNIQUE,
  `password_hash` varchar(255) NOT NULL,
  `role` varchar(20) NOT NULL, -- 'admin', 'manager', 'barber', 'customer'
  `is_active` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Customers Table
CREATE TABLE `customers` (
  `customer_id` varchar(10) NOT NULL,
  `user_id` char(36) DEFAULT NULL,
  `full_name` varchar(100) NOT NULL,
  `phone` varchar(15) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `registration_date` date DEFAULT curdate(),
  `date_of_birth` date DEFAULT NULL,
  `gender` varchar(10) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`customer_id`),
  KEY `idx_customers_phone` (`phone`),
  KEY `idx_customers_email` (`email`),
  CONSTRAINT `fk_customers_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Service Categories
CREATE TABLE `service_categories` (
  `category_id` varchar(10) NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`category_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Services Table
CREATE TABLE `services` (
  `service_id` varchar(10) NOT NULL,
  `name` varchar(100) NOT NULL,
  `category_id` varchar(10) DEFAULT NULL,
  `duration_minutes` int(11) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `cost` decimal(10,2) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`service_id`),
  CONSTRAINT `services_ibfk_1` FOREIGN KEY (`category_id`) REFERENCES `service_categories` (`category_id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 5. Staff Table
CREATE TABLE `staff` (
  `staff_id` varchar(10) NOT NULL,
  `user_id` char(36) DEFAULT NULL,
  `name` varchar(100) NOT NULL,
  `phone` varchar(15) DEFAULT NULL,
  `email` varchar(100) DEFAULT NULL,
  `role` varchar(50) NOT NULL,
  `skills` text DEFAULT NULL,
  `pay_rate` decimal(10,2) DEFAULT NULL,
  `commission_rate` decimal(5,3) DEFAULT 0.000,
  `is_active` tinyint(1) DEFAULT 1,
  `profile_photo` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`staff_id`),
  CONSTRAINT `staff_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 6. Appointments Table
CREATE TABLE `appointments` (
  `appointment_id` varchar(10) NOT NULL,
  `customer_id` varchar(10) DEFAULT NULL,
  `staff_id` varchar(10) DEFAULT NULL,
  `service_id` varchar(10) DEFAULT NULL,
  `start_time` datetime NOT NULL,
  `end_time` datetime NOT NULL,
  `status` varchar(20) DEFAULT 'pending' CHECK (`status` in ('pending','booked','confirmed','checked-in','in-service','in_progress','completed','canceled','declined','no-show')),
  `source` varchar(20) DEFAULT 'web' CHECK (`source` in ('web','phone','walk-in')),
  `notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`appointment_id`),
  CONSTRAINT `appointments_ibfk_1` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `appointments_ibfk_2` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`) ON DELETE SET NULL,
  CONSTRAINT `appointments_ibfk_3` FOREIGN KEY (`service_id`) REFERENCES `services` (`service_id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 7. Transactions Table
CREATE TABLE `transactions` (
  `transaction_id` varchar(10) NOT NULL,
  `appointment_id` varchar(10) DEFAULT NULL,
  `customer_id` varchar(10) DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL,
  `payment_method` varchar(20) NOT NULL,
  `tip_amount` decimal(10,2) DEFAULT 0.00,
  `tax_amount` decimal(10,2) DEFAULT 0.00,
  `staff_id` varchar(10) DEFAULT NULL,
  `status` varchar(20) DEFAULT 'completed',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`transaction_id`),
  CONSTRAINT `transactions_ibfk_1` FOREIGN KEY (`appointment_id`) REFERENCES `appointments` (`appointment_id`) ON DELETE SET NULL,
  CONSTRAINT `transactions_ibfk_2` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE SET NULL,
  CONSTRAINT `transactions_ibfk_3` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 8. Feedback Table
CREATE TABLE `feedback` (
  `feedback_id` int(11) NOT NULL AUTO_INCREMENT,
  `appointment_id` varchar(10) DEFAULT NULL,
  `customer_id` varchar(10) DEFAULT NULL,
  `rating` int(11) NOT NULL CHECK (`rating` >= 1 and `rating` <= 5),
  `comments` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`feedback_id`),
  CONSTRAINT `feedback_ibfk_1` FOREIGN KEY (`appointment_id`) REFERENCES `appointments` (`appointment_id`) ON DELETE CASCADE,
  CONSTRAINT `feedback_ibfk_2` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Initial Seeds
INSERT INTO `users` (`user_id`, `username`, `email`, `password_hash`, `role`, `is_active`) 
VALUES ('3c610409-c745-11f0-b6be-54e1ad8d90ee', 'admin', 'admin@admin.com', 'password', 'admin', 1);

INSERT INTO `service_categories` (`category_id`, `name`) VALUES 
('CAT001', 'Haircut'), ('CAT002', 'Styling'), ('CAT003', 'Beard');
*/

// Create database connection
function getDBConnection() {
    $conn = null;
    $passwords = [DB_PASS, '', 'password', 'root'];
    
    foreach (array_unique($passwords) as $pwd) {
        try {
            $conn = @new mysqli(DB_HOST, DB_USER, $pwd, DB_NAME);
            if (!$conn->connect_error) {
                return $conn;
            }
        } catch (\Throwable $e) {
            // continue to try next password
        }
    }
    
    die(json_encode([
        'success' => false,
        'error' => 'Database connection failed: Access denied or database ' . DB_NAME . ' does not exist.'
    ]));
}

// Helper function to send JSON response
function sendResponse($success, $data = null, $error = null) {
    // Clear any output buffer
    if (ob_get_level()) {
        ob_clean();
    }
    
    echo json_encode([
        'success' => $success,
        'data' => $data,
        'error' => $error
    ]);
    exit();
}

// Helper to save base64 images to uploads directory and return public URL
function saveBase64Image($base64String, $prefix = 'img') {
    if (empty($base64String)) {
        return null;
    }
    
    // If it's already an HTTP URL or local path, return as is
    if (strpos($base64String, 'http://') === 0 || strpos($base64String, 'https://') === 0) {
        return $base64String;
    }
    
    // Check if it's base64 data
    if (strpos($base64String, 'base64,') !== false) {
        $parts = explode('base64,', $base64String);
        $base64Data = $parts[1];
    } else {
        $base64Data = $base64String;
    }
    
    $cleanData = preg_replace('/\s+/', '', $base64Data);
    $imageData = base64_decode($cleanData);
    if ($imageData === false || strlen($imageData) === 0) {
        return null;
    }
    
    $uploadDir = __DIR__ . '/uploads/';
    if (!is_dir($uploadDir)) {
        @mkdir($uploadDir, 0777, true);
    }
    
    $filename = $prefix . '_' . uniqid() . '_' . time() . '.jpg';
    $filepath = $uploadDir . $filename;
    
    if (file_put_contents($filepath, $imageData) !== false) {
        $protocol = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off' || (isset($_SERVER['SERVER_PORT']) && $_SERVER['SERVER_PORT'] == 443)) ? "https://" : "http://";
        $host = $_SERVER['HTTP_HOST'] ?? 'localhost';
        return $protocol . $host . '/barber_api/uploads/' . $filename;
    }
    
    return null;
}
?>
