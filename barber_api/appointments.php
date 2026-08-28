<?php
require_once 'config.php';

$conn = getDBConnection();
$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        // Check if requesting a specific appointment by ID
        $appointment_id = $_GET['appointment_id'] ?? '';
        
        if (!empty($appointment_id)) {
            // Get single appointment by ID
            $stmt = $conn->prepare("
                SELECT a.*, c.full_name as customer_name, c.phone as customer_phone, c.profile_picture as customer_photo,
                       s.name as staff_name, s.profile_photo as staff_photo, sv.name as service_name,
                       sv.image_url as service_image, sv.description, sv.price as service_price, sv.duration_minutes,
                       cat.name as category_name,
                       DATE(a.start_time) as date,
                       TIME(a.start_time) as time
                FROM appointments a
                LEFT JOIN customers c ON a.customer_id = c.customer_id
                LEFT JOIN staff s ON a.staff_id = s.staff_id
                LEFT JOIN services sv ON a.service_id = sv.service_id
                LEFT JOIN service_categories cat ON sv.category_id = cat.category_id
                WHERE a.appointment_id = ?
            ");
            $stmt->bind_param("s", $appointment_id);
            $stmt->execute();
            $result = $stmt->get_result();
            
            if ($result && $result->num_rows > 0) {
                $appointment = $result->fetch_assoc();
                if (!empty($appointment['date'])) {
                    $dateObj = DateTime::createFromFormat('Y-m-d', $appointment['date']);
                    if ($dateObj) {
                        $appointment['date'] = $dateObj->format('M d, Y');
                    }
                }
                if (!empty($appointment['time'])) {
                    $timeObj = DateTime::createFromFormat('H:i:s', $appointment['time']);
                    if ($timeObj) {
                        $appointment['time'] = $timeObj->format('h:i A');
                    }
                }
                sendResponse(true, $appointment);
            } else {
                sendResponse(false, null, 'Appointment not found');
            }
            $stmt->close();
        } else {
            // Get appointments with flexible filters
            $customer_id = $_GET['customer_id'] ?? '';
            $staff_id = $_GET['staff_id'] ?? '';
            $date_filter = $_GET['date'] ?? '';
            $upcoming_only = isset($_GET['upcoming_only']) && $_GET['upcoming_only'] == '1';
            $today = date('Y-m-d 00:00:00');
            $todayDate = date('Y-m-d');
            
            $query = "
                SELECT a.*, c.full_name as customer_name, c.phone as customer_phone, c.profile_picture as customer_photo,
                       s.name as staff_name, s.profile_photo as staff_photo, sv.name as service_name,
                       sv.image_url as service_image,
                       sv.description, sv.price as service_price, sv.duration_minutes,
                       cat.name as category_name,
                       DATE(a.start_time) as date,
                       TIME(a.start_time) as time
                FROM appointments a
                LEFT JOIN customers c ON a.customer_id = c.customer_id
                LEFT JOIN staff s ON a.staff_id = s.staff_id
                LEFT JOIN services sv ON a.service_id = sv.service_id
                LEFT JOIN service_categories cat ON sv.category_id = cat.category_id
                WHERE 1=1";
            
            $params = [];
            $types = '';
            
            // Filter by customer_id if provided
            if (!empty($customer_id)) {
                $query .= " AND a.customer_id = ?";
                $params[] = $customer_id;
                $types .= 's';
            }
            
            // Filter by staff_id if provided (for barber viewing his cuts)
            if (!empty($staff_id)) {
                $query .= " AND a.staff_id = ?";
                $params[] = $staff_id;
                $types .= 's';
            }
            
            // Filter by specific date or 'today'
            if ($date_filter === 'today') {
                $query .= " AND DATE(a.start_time) = ?";
                $params[] = $todayDate;
                $types .= 's';
            } else if (!empty($date_filter) && $date_filter !== 'all') {
                $query .= " AND DATE(a.start_time) = ?";
                $params[] = $date_filter;
                $types .= 's';
            }
            
            // Filter for upcoming appointments only
            if ($upcoming_only) {
                $query .= " AND a.start_time >= ?";
                $params[] = $today;
                $types .= 's';
            }
            
            // Default exclude cancelled if not customer or barber view
            if (empty($customer_id) && empty($staff_id)) {
                $query .= " AND a.status != 'canceled'";
            }
            
            // Order by start_time
            if ($upcoming_only || !empty($staff_id) || $date_filter === 'today') {
                $query .= " ORDER BY a.start_time ASC";
            } else {
                $query .= " ORDER BY a.start_time DESC";
            }
            
            if (!empty($params)) {
                $stmt = $conn->prepare($query);
                $stmt->bind_param($types, ...$params);
                $stmt->execute();
                $result = $stmt->get_result();
            } else {
                $result = $conn->query($query);
            }
            
            $appointments = [];
            if ($result) {
                while ($row = $result->fetch_assoc()) {
                    if (!empty($row['date'])) {
                        $dateObj = DateTime::createFromFormat('Y-m-d', $row['date']);
                        if ($dateObj) {
                            $row['date'] = $dateObj->format('M d, Y');
                        }
                    }
                    if (!empty($row['time'])) {
                        $timeObj = DateTime::createFromFormat('H:i:s', $row['time']);
                        if ($timeObj) {
                            $row['time'] = $timeObj->format('h:i A');
                        }
                    }
                    $appointments[] = $row;
                }
            }
            if (isset($stmt)) {
                $stmt->close();
            }
            sendResponse(true, $appointments);
        }
        break;
        
    case 'POST':
        // Create appointment
        $input = json_decode(file_get_contents('php://input'), true);
        
        if (empty($input['customer_id']) || empty($input['service_id']) || empty($input['start_time'])) {
            sendResponse(false, null, 'Customer ID, Service ID, and Start Time are required');
            break;
        }
        
        $appointment_id = 'APT' . str_pad(rand(1, 99999), 5, '0', STR_PAD_LEFT);
        
        // Calculate end_time based on service duration
        $start_time = $input['start_time'];
        $duration_minutes = 30; // Default
        
        $getServiceStmt = $conn->prepare("SELECT duration_minutes FROM services WHERE service_id = ?");
        $getServiceStmt->bind_param("s", $input['service_id']);
        $getServiceStmt->execute();
        $serviceResult = $getServiceStmt->get_result();
        if ($serviceResult && $serviceResult->num_rows > 0) {
            $service = $serviceResult->fetch_assoc();
            $duration_minutes = $service['duration_minutes'] ?? 30;
        }
        $getServiceStmt->close();
        
        $start_datetime = new DateTime($start_time);
        $start_datetime->modify("+{$duration_minutes} minutes");
        $end_time = $start_datetime->format('Y-m-d H:i:s');
        
        $staff_id = $input['staff_id'] ?? null;
        $notes = $input['notes'] ?? null;
        $status = $input['status'] ?? 'pending';
        
        $stmt = $conn->prepare("
            INSERT INTO appointments (appointment_id, customer_id, staff_id, service_id, start_time, end_time, status, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ");
        $stmt->bind_param("ssssssss", 
            $appointment_id,
            $input['customer_id'],
            $staff_id,
            $input['service_id'],
            $start_time,
            $end_time,
            $status,
            $notes
        );
        
        if ($stmt->execute()) {
            sendResponse(true, ['appointment_id' => $appointment_id]);
        } else {
            sendResponse(false, null, 'Failed to create appointment: ' . $stmt->error);
        }
        $stmt->close();
        break;
        
    case 'PUT':
        // Update appointment (Status, notes, reschedule, etc.)
        $input = json_decode(file_get_contents('php://input'), true);
        $appointment_id = $input['appointment_id'] ?? '';
        
        if (empty($appointment_id)) {
            sendResponse(false, null, 'Appointment ID is required');
            break;
        }
        
        $updates = [];
        $params = [];
        $types = '';
        
        // Handle reschedule: combine date and time into start_time, then calculate end_time
        if (isset($input['date']) && isset($input['time'])) {
            $start_time = $input['date'] . ' ' . $input['time'];
            
            $getAppointmentStmt = $conn->prepare("SELECT service_id FROM appointments WHERE appointment_id = ?");
            $getAppointmentStmt->bind_param("s", $appointment_id);
            $getAppointmentStmt->execute();
            $appointmentResult = $getAppointmentStmt->get_result();
            
            if ($appointmentResult && $appointmentResult->num_rows > 0) {
                $appointment = $appointmentResult->fetch_assoc();
                $service_id = $appointment['service_id'];
                
                $getServiceStmt = $conn->prepare("SELECT duration_minutes FROM services WHERE service_id = ?");
                $getServiceStmt->bind_param("s", $service_id);
                $getServiceStmt->execute();
                $serviceResult = $getServiceStmt->get_result();
                
                if ($serviceResult && $serviceResult->num_rows > 0) {
                    $service = $serviceResult->fetch_assoc();
                    $duration_minutes = $service['duration_minutes'] ?? 30;
                    
                    $start_datetime = new DateTime($start_time);
                    $start_datetime->modify("+{$duration_minutes} minutes");
                    $end_time = $start_datetime->format('Y-m-d H:i:s');
                    
                    $updates[] = "start_time = ?";
                    $params[] = $start_time;
                    $types .= 's';
                    
                    $updates[] = "end_time = ?";
                    $params[] = $end_time;
                    $types .= 's';
                }
                $getServiceStmt->close();
            }
            $getAppointmentStmt->close();
        }
        
        // Handle other fields (status, notes, customer_id, staff_id, service_id)
        $fields = ['status', 'notes', 'start_time', 'end_time', 'customer_id', 'staff_id', 'service_id'];
        foreach ($fields as $field) {
            if (($field === 'start_time' || $field === 'end_time') && isset($input['date']) && isset($input['time'])) {
                continue;
            }
            
            if (isset($input[$field])) {
                $updates[] = "$field = ?";
                $params[] = $input[$field];
                $types .= 's';
            }
        }
        
        if (empty($updates)) {
            sendResponse(false, null, 'No fields to update');
            break;
        }
        
        $params[] = $appointment_id;
        $types .= 's';
        
        $query = "UPDATE appointments SET " . implode(', ', $updates) . " WHERE appointment_id = ?";
        $stmt = $conn->prepare($query);
        $stmt->bind_param($types, ...$params);
        $stmt->execute();
        
        if ($stmt->affected_rows >= 0) {
            sendResponse(true, ['appointment_id' => $appointment_id, 'updated' => true]);
        } else {
            sendResponse(false, null, 'Failed to update appointment: ' . $stmt->error);
        }
        $stmt->close();
        break;
        
    default:
        sendResponse(false, null, 'Method not allowed');
}

$conn->close();
?>
