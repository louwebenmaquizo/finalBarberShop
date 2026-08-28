<?php
require_once 'config.php';

$conn = getDBConnection();
$method = $_SERVER['REQUEST_METHOD'];

if ($method !== 'GET') {
    sendResponse(false, null, 'Method not allowed');
}

// Get dashboard statistics
$dashboardData = [];

// 1. Today's Bookings Count (all non-canceled statuses)
$todayBookingsResult = $conn->query("
    SELECT COUNT(*) as count 
    FROM appointments 
    WHERE DATE(start_time) = CURDATE() 
    AND status NOT IN ('canceled', 'cancelled', 'no-show')
");
$todayBookings = $todayBookingsResult->fetch_assoc()['count'] ?? 0;

// 2. Total Bookings Count (all non-canceled)
$totalBookingsResult = $conn->query("
    SELECT COUNT(*) as count 
    FROM appointments
    WHERE status NOT IN ('canceled', 'cancelled')
");
$totalBookings = $totalBookingsResult->fetch_assoc()['count'] ?? 0;

// 3. Total Barbers Count
$totalBarbersResult = $conn->query("SELECT COUNT(*) as count FROM staff WHERE is_active = TRUE");
$totalBarbers = $totalBarbersResult->fetch_assoc()['count'] ?? 0;

// 4. Revenue Today
$revenueResult = $conn->query("
    SELECT COALESCE(SUM(amount + tip_amount), 0) as revenue 
    FROM transactions 
    WHERE DATE(created_at) = CURDATE() 
    AND status = 'completed'
");
$revenueToday = $revenueResult->fetch_assoc()['revenue'] ?? 0;

// 5. Weekly Analytics (bookings per day for last 7 days)
$analyticsResult = $conn->query("
    SELECT 
        DATE(start_time) as date,
        COUNT(*) as count
    FROM appointments
    WHERE start_time >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
    AND status NOT IN ('canceled', 'cancelled')
    GROUP BY DATE(start_time)
    ORDER BY date ASC
");
$weeklyData = [];
$days = [];
$dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

// Initialize last 7 days
for ($i = 6; $i >= 0; $i--) {
    $date = date('Y-m-d', strtotime("-$i days"));
    $dayOfWeek = (int)date('w', strtotime($date));
    $days[] = $dayNames[$dayOfWeek];
    $weeklyData[$date] = 0;
}

// Map database results
while ($row = $analyticsResult->fetch_assoc()) {
    $date = $row['date'];
    if (isset($weeklyData[$date])) {
        $weeklyData[$date] = (int)$row['count'];
    }
}

$analyticsValues = array_values($weeklyData);

// 6. Next Client (next upcoming non-canceled appointment)
$nextClientResult = $conn->query("
    SELECT 
        a.appointment_id,
        a.start_time,
        a.end_time,
        a.status,
        c.full_name as customer_name,
        s.name as staff_name,
        sv.name as service_name
    FROM appointments a
    LEFT JOIN customers c ON a.customer_id = c.customer_id
    LEFT JOIN staff s ON a.staff_id = s.staff_id
    LEFT JOIN services sv ON a.service_id = sv.service_id
    WHERE a.start_time >= NOW()
    AND a.status NOT IN ('canceled', 'cancelled', 'no-show', 'declined')
    ORDER BY a.start_time ASC
    LIMIT 1
");
$nextClient = $nextClientResult->fetch_assoc();

// 7. Recent Bookings (last 10)
$recentBookingsResult = $conn->query("
    SELECT 
        a.appointment_id,
        a.start_time,
        a.end_time,
        a.status,
        c.full_name as customer_name,
        s.name as staff_name,
        sv.name as service_name,
        sv.price as service_price
    FROM appointments a
    LEFT JOIN customers c ON a.customer_id = c.customer_id
    LEFT JOIN staff s ON a.staff_id = s.staff_id
    LEFT JOIN services sv ON a.service_id = sv.service_id
    ORDER BY a.start_time DESC
    LIMIT 10
");
$recentBookings = [];
while ($row = $recentBookingsResult->fetch_assoc()) {
    $recentBookings[] = [
        'appointment_id' => $row['appointment_id'],
        'time'           => date('g:i A', strtotime($row['start_time'])),
        'date_label'     => date('M d, Y', strtotime($row['start_time'])),
        'customer'       => $row['customer_name'] ?? 'Unknown',
        'service'        => $row['service_name'] ?? 'N/A',
        'price'          => $row['service_price'] ?? '0.00',
        'schedule'       => date('g:i A', strtotime($row['start_time'])) . ' - ' . date('g:i A', strtotime($row['end_time'])),
        'employee'       => $row['staff_name'] ?? 'N/A',
        'status'         => $row['status'] ?? 'booked',
        'date'           => $row['start_time'],
    ];
}

// 8. Top Barbers (active staff with appointment counts and profile photos)
$topBarbersResult = $conn->query("
    SELECT 
        s.staff_id,
        s.name,
        s.role,
        s.profile_photo,
        COUNT(a.appointment_id) as total_appointments
    FROM staff s
    LEFT JOIN appointments a ON s.staff_id = a.staff_id 
        AND a.status NOT IN ('canceled', 'cancelled')
    WHERE s.is_active = TRUE
    GROUP BY s.staff_id, s.name, s.role, s.profile_photo
    ORDER BY total_appointments DESC, s.name ASC
    LIMIT 50
");
$topBarbers = [];
while ($row = $topBarbersResult->fetch_assoc()) {
    $topBarbers[] = [
        'staff_id'            => $row['staff_id'],
        'name'                => $row['name'],
        'role'                => $row['role'],
        'profile_photo'       => $row['profile_photo'],
        'total_appointments'  => (int)$row['total_appointments'],
    ];
}

// 9. Monthly Revenue Stats (last 6 months)
$monthlyRevenueResult = $conn->query("
    SELECT 
        DATE_FORMAT(created_at, '%b') as month,
        COALESCE(SUM(amount + tip_amount), 0) as revenue
    FROM transactions
    WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
    AND status = 'completed'
    GROUP BY DATE_FORMAT(created_at, '%Y-%m')
    ORDER BY MIN(created_at) ASC
");
$monthlyRevenue = [];
while ($row = $monthlyRevenueResult->fetch_assoc()) {
    $monthlyRevenue[] = [
        'month'   => $row['month'],
        'revenue' => (float)$row['revenue'],
    ];
}

// 10. Pending Appointments Count
$pendingResult = $conn->query("
    SELECT COUNT(*) as count FROM appointments WHERE status = 'pending'
");
$pendingCount = $pendingResult->fetch_assoc()['count'] ?? 0;

// Format next client data
$formattedNextClient = null;
if ($nextClient) {
    $startTime = strtotime($nextClient['start_time']);
    $endTime   = strtotime($nextClient['end_time']);
    $formattedNextClient = [
        'customer_name' => $nextClient['customer_name'] ?? 'Unknown',
        'date'          => date('F j, Y', $startTime),
        'time'          => date('g:i A', $startTime),
        'end_time'      => date('g:i A', $endTime),
        'service'       => $nextClient['service_name'] ?? 'N/A',
        'employee'      => $nextClient['staff_name'] ?? 'N/A',
        'status'        => $nextClient['status'] ?? 'booked',
    ];
}

// Compile dashboard data
$dashboardData = [
    'stats' => [
        'today_bookings'  => (int)$todayBookings,
        'total_bookings'  => (int)$totalBookings,
        'total_barbers'   => (int)$totalBarbers,
        'revenue_today'   => (float)$revenueToday,
        'pending_count'   => (int)$pendingCount,
    ],
    'analytics' => [
        'days'   => $days,
        'values' => $analyticsValues,
    ],
    'next_client'     => $formattedNextClient,
    'recent_bookings' => $recentBookings,
    'top_barbers'     => $topBarbers,
    'monthly_revenue' => $monthlyRevenue,
];

sendResponse(true, $dashboardData);
$conn->close();
?>
