-- LEGACY REFERENCE ONLY. Do not import this file into production.
-- The active PostgreSQL schema is in supabase/migrations. The sample MySQL
-- administrator below used a plaintext password and is intentionally not
-- migrated to Supabase Auth.

CREATE DATABASE IF NOT EXISTS `barber`;
USE `barber`;

-- 1. Users Table
CREATE TABLE IF NOT EXISTS `users` (
  `user_id` char(36) NOT NULL DEFAULT (uuid()),
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
CREATE TABLE IF NOT EXISTS `customers` (
  `customer_id` varchar(10) NOT NULL,
  `user_id` char(36) DEFAULT NULL,
  `full_name` varchar(100) NOT NULL,
  `phone` varchar(15) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `registration_date` date DEFAULT (curdate()),
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
CREATE TABLE IF NOT EXISTS `service_categories` (
  `category_id` varchar(10) NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`category_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Services Table
CREATE TABLE IF NOT EXISTS `services` (
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
CREATE TABLE IF NOT EXISTS `staff` (
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
CREATE TABLE IF NOT EXISTS `appointments` (
  `appointment_id` varchar(10) NOT NULL,
  `customer_id` varchar(10) DEFAULT NULL,
  `staff_id` varchar(10) DEFAULT NULL,
  `service_id` varchar(10) DEFAULT NULL,
  `start_time` datetime NOT NULL,
  `end_time` datetime NOT NULL,
  `status` varchar(20) DEFAULT 'booked' CHECK (`status` in ('booked','checked-in','in-service','completed','canceled','no-show')),
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
CREATE TABLE IF NOT EXISTS `transactions` (
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
CREATE TABLE IF NOT EXISTS `feedback` (
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
VALUES ('3c610409-c745-11f0-b6be-54e1ad8d90ee', 'admin', 'admin@admin.com', 'password', 'admin', 1)
ON DUPLICATE KEY UPDATE `username` = VALUES(`username`);

INSERT INTO `service_categories` (`category_id`, `name`) VALUES 
('CAT001', 'Haircut'), ('CAT002', 'Styling'), ('CAT003', 'Beard')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);
