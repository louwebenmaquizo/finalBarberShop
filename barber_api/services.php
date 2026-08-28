<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once 'config.php';

try {
    $conn = getDBConnection();
    $method = $_SERVER['REQUEST_METHOD'];
    
    switch ($method) {
        case 'GET':
            // Check if include_inactive parameter is set
            $includeInactive = isset($_GET['include_inactive']) && 
                               ($_GET['include_inactive'] == '1' || 
                                $_GET['include_inactive'] == 'true' || 
                                $_GET['include_inactive'] == 'yes');
            
            // Check if getting a specific service by ID
            if (isset($_GET['service_id'])) {
                $serviceId = $conn->real_escape_string($_GET['service_id']);
                $sql = "SELECT s.*, sc.name as category_name 
                        FROM services s 
                        LEFT JOIN service_categories sc ON s.category_id = sc.category_id 
                        WHERE s.service_id = '$serviceId'";
            } else {
                // Build query based on include_inactive parameter
                if ($includeInactive) {
                    $sql = "SELECT s.*, sc.name as category_name 
                            FROM services s 
                            LEFT JOIN service_categories sc ON s.category_id = sc.category_id 
                            ORDER BY s.name";
                } else {
                    $sql = "SELECT s.*, sc.name as category_name 
                            FROM services s 
                            LEFT JOIN service_categories sc ON s.category_id = sc.category_id 
                            WHERE s.is_active = 1 
                            ORDER BY s.name";
                }
            }
            
            $result = $conn->query($sql);
            
            if ($result) {
                if (isset($_GET['service_id'])) {
                    $service = $result->fetch_assoc();
                    if ($service) {
                        sendResponse(true, $service);
                    } else {
                        sendResponse(false, null, 'Service not found');
                    }
                } else {
                    $services = [];
                    while ($row = $result->fetch_assoc()) {
                        $services[] = $row;
                    }
                    sendResponse(true, $services);
                }
            } else {
                throw new Exception("Query failed: " . $conn->error);
            }
            break;
            
        case 'POST':
            // Create new service
            $data = json_decode(file_get_contents('php://input'), true);
            if (!$data || empty($data['name'])) {
                sendResponse(false, null, 'Service name is required');
                break;
            }
            
            $name = trim($data['name']);
            
            // 1. Check for Duplicate Service Name (case-insensitive)
            $nameCheck = $conn->prepare("SELECT service_id FROM services WHERE LOWER(TRIM(name)) = LOWER(?)");
            $nameCheck->bind_param("s", $name);
            $nameCheck->execute();
            if ($nameCheck->get_result()->num_rows > 0) {
                sendResponse(false, null, 'A service with the name "' . $name . '" already exists in the catalog');
                $nameCheck->close();
                break;
            }
            $nameCheck->close();

            $categoryId = isset($data['category_id']) && $data['category_id'] !== '' ? trim($data['category_id']) : null;
            $duration = intval($data['duration_minutes'] ?? 30);
            $price = floatval($data['price'] ?? 0.0);
            $cost = isset($data['cost']) && $data['cost'] !== '' && $data['cost'] !== null ? floatval($data['cost']) : 0.0;
            $description = isset($data['description']) && $data['description'] !== '' ? trim($data['description']) : null;
            $raw_image = isset($data['image_url']) && $data['image_url'] !== '' ? $data['image_url'] : (isset($data['photo']) && $data['photo'] !== '' ? $data['photo'] : null);
            $image_url = saveBase64Image($raw_image, 'service');
            $isActive = isset($data['is_active']) ? ($data['is_active'] ? 1 : 0) : 1;
            
            // Generate service_id
            $serviceId = 'S' . str_pad(rand(1, 9999), 4, '0', STR_PAD_LEFT);
            
            $stmt = $conn->prepare("INSERT INTO services (service_id, name, category_id, duration_minutes, price, cost, description, image_url, is_active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
            $stmt->bind_param("sssiddssi", 
                $serviceId, 
                $name, 
                $categoryId, 
                $duration, 
                $price, 
                $cost, 
                $description, 
                $image_url, 
                $isActive
            );
            
            if ($stmt->execute()) {
                sendResponse(true, [
                    'service_id' => $serviceId,
                    'name' => $name,
                    'image_url' => $image_url,
                    'message' => 'Service created successfully'
                ]);
            } else {
                sendResponse(false, null, 'Insert failed: ' . $stmt->error);
            }
            $stmt->close();
            break;
            
        case 'PUT':
            // Update service
            $data = json_decode(file_get_contents('php://input'), true);
            
            if (!isset($data['service_id']) || empty($data['service_id'])) {
                sendResponse(false, null, "service_id is required");
                break;
            }
            
            $serviceId = $data['service_id'];
            
            // Fetch current record
            $curStmt = $conn->prepare("SELECT * FROM services WHERE service_id = ?");
            $curStmt->bind_param("s", $serviceId);
            $curStmt->execute();
            $curRes = $curStmt->get_result();
            if ($curRes->num_rows == 0) {
                sendResponse(false, null, "Service not found");
                $curStmt->close();
                break;
            }
            $current = $curRes->fetch_assoc();
            $curStmt->close();

            // Check duplicate name if name changed
            if (isset($data['name']) && !empty($data['name'])) {
                $name = trim($data['name']);
                $nameCheck = $conn->prepare("SELECT service_id FROM services WHERE LOWER(TRIM(name)) = LOWER(?) AND service_id != ?");
                $nameCheck->bind_param("ss", $name, $serviceId);
                $nameCheck->execute();
                if ($nameCheck->get_result()->num_rows > 0) {
                    sendResponse(false, null, 'Another service with the name "' . $name . '" already exists in the catalog');
                    $nameCheck->close();
                    break;
                }
                $nameCheck->close();
            } else {
                $name = $current['name'];
            }

            $categoryId = array_key_exists('category_id', $data) ? ($data['category_id'] !== '' ? $data['category_id'] : null) : $current['category_id'];
            $duration = isset($data['duration_minutes']) ? intval($data['duration_minutes']) : intval($current['duration_minutes']);
            $price = isset($data['price']) ? floatval($data['price']) : floatval($current['price']);
            $cost = isset($data['cost']) && $data['cost'] !== '' && $data['cost'] !== null ? floatval($data['cost']) : floatval($current['cost'] ?? 0.0);
            $description = array_key_exists('description', $data) ? $data['description'] : $current['description'];
            
            // Image handling: check 'image_url' or 'photo'
            $image_url = $current['image_url'];
            if (array_key_exists('image_url', $data)) {
                $image_url = $data['image_url'] !== '' ? $data['image_url'] : null;
            } else if (array_key_exists('photo', $data)) {
                $image_url = $data['photo'] !== '' ? $data['photo'] : null;
            }
            $image_url = saveBase64Image($image_url, 'service');

            $isActive = array_key_exists('is_active', $data) ? ($data['is_active'] ? 1 : 0) : intval($current['is_active']);

            $stmt = $conn->prepare("UPDATE services SET name = ?, category_id = ?, duration_minutes = ?, price = ?, cost = ?, description = ?, image_url = ?, is_active = ? WHERE service_id = ?");
            $stmt->bind_param("ssiddssis", 
                $name, 
                $categoryId, 
                $duration, 
                $price, 
                $cost, 
                $description, 
                $image_url, 
                $isActive, 
                $serviceId
            );
            
            if ($stmt->execute()) {
                sendResponse(true, [
                    'service_id' => $serviceId,
                    'name' => $name,
                    'image_url' => $image_url,
                    'message' => 'Service updated successfully'
                ]);
            } else {
                sendResponse(false, null, 'Update failed: ' . $stmt->error);
            }
            $stmt->close();
            break;
            
        case 'DELETE':
            $data = json_decode(file_get_contents('php://input'), true);
            $serviceId = $data['service_id'] ?? $_GET['service_id'] ?? '';
            
            if (empty($serviceId)) {
                sendResponse(false, null, "service_id is required");
                break;
            }
            
            $stmt = $conn->prepare("DELETE FROM services WHERE service_id = ?");
            $stmt->bind_param("s", $serviceId);
            
            if ($stmt->execute()) {
                sendResponse(true, ['message' => 'Service deleted successfully']);
            } else {
                sendResponse(false, null, 'Delete failed: ' . $stmt->error);
            }
            $stmt->close();
            break;
            
        default:
            sendResponse(false, null, "Method not allowed");
    }
    
    $conn->close();
    
} catch (Exception $e) {
    sendResponse(false, null, $e->getMessage());
}
?>
