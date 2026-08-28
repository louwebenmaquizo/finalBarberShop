<?php
require_once 'config.php';

$conn = getDBConnection();
$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        // Get all categories with service count
        $query = "SELECT 
                    sc.category_id,
                    sc.name,
                    sc.description,
                    sc.created_at,
                    COUNT(s.service_id) as service_count
                  FROM service_categories sc
                  LEFT JOIN services s ON sc.category_id = s.category_id
                  GROUP BY sc.category_id, sc.name, sc.description, sc.created_at
                  ORDER BY sc.name ASC";
        
        $result = $conn->query($query);
        $categories = [];
        
        if ($result) {
            while ($row = $result->fetch_assoc()) {
                $row['service_count'] = intval($row['service_count'] ?? 0);
                $categories[] = $row;
            }
            sendResponse(true, $categories);
        } else {
            sendResponse(false, null, 'Error fetching categories: ' . $conn->error);
        }
        break;

    case 'POST':
        // Create a new category
        $input = json_decode(file_get_contents('php://input'), true);
        if (!$input || empty($input['name'])) {
            sendResponse(false, null, 'Category name is required');
            break;
        }

        $name = trim($input['name']);
        $description = isset($input['description']) && $input['description'] !== '' ? trim($input['description']) : null;

        // Check for duplicate category name (case-insensitive)
        $checkStmt = $conn->prepare("SELECT category_id FROM service_categories WHERE LOWER(TRIM(name)) = LOWER(?)");
        $checkStmt->bind_param("s", $name);
        $checkStmt->execute();
        if ($checkStmt->get_result()->num_rows > 0) {
            sendResponse(false, null, 'A category named "' . $name . '" already exists');
            $checkStmt->close();
            break;
        }
        $checkStmt->close();
        
        // Generate unique category_id (e.g. CAT00001 to CAT99999)
        $category_id = 'CAT' . str_pad(rand(1, 99999), 5, '0', STR_PAD_LEFT);

        $stmt = $conn->prepare("INSERT INTO service_categories (category_id, name, description) VALUES (?, ?, ?)");
        $stmt->bind_param("sss", $category_id, $name, $description);

        if ($stmt->execute()) {
            sendResponse(true, [
                'category_id' => $category_id,
                'name' => $name,
                'description' => $description,
                'message' => 'Category created successfully'
            ]);
        } else {
            sendResponse(false, null, 'Failed to create category: ' . $stmt->error);
        }
        $stmt->close();
        break;

    case 'PUT':
        // Update category
        $input = json_decode(file_get_contents('php://input'), true);
        if (!$input || empty($input['category_id']) || empty($input['name'])) {
            sendResponse(false, null, 'Category ID and name are required');
            break;
        }

        $category_id = trim($input['category_id']);
        $name = trim($input['name']);
        $description = isset($input['description']) ? trim($input['description']) : null;

        // Check for duplicate category name excluding current category
        $checkStmt = $conn->prepare("SELECT category_id FROM service_categories WHERE LOWER(TRIM(name)) = LOWER(?) AND category_id != ?");
        $checkStmt->bind_param("ss", $name, $category_id);
        $checkStmt->execute();
        if ($checkStmt->get_result()->num_rows > 0) {
            sendResponse(false, null, 'Another category named "' . $name . '" already exists');
            $checkStmt->close();
            break;
        }
        $checkStmt->close();

        $stmt = $conn->prepare("UPDATE service_categories SET name = ?, description = ? WHERE category_id = ?");
        $stmt->bind_param("sss", $name, $description, $category_id);

        if ($stmt->execute()) {
            sendResponse(true, [
                'category_id' => $category_id,
                'name' => $name,
                'description' => $description,
                'message' => 'Category updated successfully'
            ]);
        } else {
            sendResponse(false, null, 'Failed to update category: ' . $stmt->error);
        }
        $stmt->close();
        break;

    case 'DELETE':
        // Delete category
        $input = json_decode(file_get_contents('php://input'), true);
        $category_id = $input['category_id'] ?? $_GET['category_id'] ?? '';

        if (empty($category_id)) {
            sendResponse(false, null, 'Category ID is required');
            break;
        }

        // Services pointing to this category will automatically have category_id set to NULL by foreign key
        $stmt = $conn->prepare("DELETE FROM service_categories WHERE category_id = ?");
        $stmt->bind_param("s", $category_id);

        if ($stmt->execute()) {
            sendResponse(true, ['message' => 'Category deleted successfully']);
        } else {
            sendResponse(false, null, 'Failed to delete category: ' . $stmt->error);
        }
        $stmt->close();
        break;

    default:
        sendResponse(false, null, 'Method not allowed');
}

$conn->close();
?>
