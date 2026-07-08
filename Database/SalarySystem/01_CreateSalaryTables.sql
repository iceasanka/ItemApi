/*
    Salary Management System - Database creation script
    Target: SQL Server
    Database: easyway (see appsettings.json -> ConnectionStrings:DefaultConnection)

    Safe to re-run: every object is created only if it does not already exist.
    Run this whole file in SQL Server Management Studio (or sqlcmd) against the target database.
*/

USE [easyway];
GO

--------------------------------------------------------------------------------
-- 1. z_tb_SalaryConfig  (global default salary settings - single row)
--------------------------------------------------------------------------------
IF OBJECT_ID(N'[dbo].[z_tb_SalaryConfig]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[z_tb_SalaryConfig] (
        [ConfigId]              INT             IDENTITY(1,1) NOT NULL,
        [BasicSalary]           DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryConfig_BasicSalary] DEFAULT (17500),
        [ByShop]                DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryConfig_ByShop] DEFAULT (5000),
        [AttendanceBonus]       DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryConfig_AttendanceBonus] DEFAULT (2000),
        [OtRate]                DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryConfig_OtRate] DEFAULT (150),
        [MhPay]                 DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryConfig_MhPay] DEFAULT (1800),
        [MhOtRate]              DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryConfig_MhOtRate] DEFAULT (200),
        [TargetBonus]           DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryConfig_TargetBonus] DEFAULT (0),
        [IsTargetBonusEnabled]  BIT             NOT NULL CONSTRAINT [DF_SalaryConfig_IsTargetBonusEnabled] DEFAULT (0),
        [ModifiedDate]          DATETIME2       NOT NULL CONSTRAINT [DF_SalaryConfig_ModifiedDate] DEFAULT (SYSDATETIME()),
        CONSTRAINT [PK_SalaryConfig] PRIMARY KEY CLUSTERED ([ConfigId])
    );
END;
GO

-- Seed the single global config row if the table is empty
IF NOT EXISTS (SELECT 1 FROM [dbo].[z_tb_SalaryConfig])
BEGIN
    INSERT INTO [dbo].[z_tb_SalaryConfig]
        ([BasicSalary], [ByShop], [AttendanceBonus], [OtRate], [MhPay], [MhOtRate], [TargetBonus], [IsTargetBonusEnabled])
    VALUES
        (17500, 5000, 2000, 150, 1800, 200, 0, 0);
END;
GO

--------------------------------------------------------------------------------
-- 2. z_tb_SalaryEmployee  (employees, with optional per-employee overrides)
--------------------------------------------------------------------------------
IF OBJECT_ID(N'[dbo].[z_tb_SalaryEmployee]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[z_tb_SalaryEmployee] (
        [EmployeeId]                    INT             IDENTITY(1,1) NOT NULL,
        [EmployeeName]                  NVARCHAR(150)   NOT NULL,
        [JoinDate]                      DATE            NOT NULL,
        [Status]                        NVARCHAR(20)    NOT NULL CONSTRAINT [DF_SalaryEmployee_Status] DEFAULT ('Active'),

        -- NULL = use the matching column from z_tb_SalaryConfig
        [BasicOverride]                 DECIMAL(18,2)   NULL,
        [ByShopOverride]                DECIMAL(18,2)   NULL,
        [AttendanceBonusOverride]       DECIMAL(18,2)   NULL,
        [OtRateOverride]                DECIMAL(18,2)   NULL,
        [MhPayOverride]                 DECIMAL(18,2)   NULL,
        [MhOtRateOverride]              DECIMAL(18,2)   NULL,
        [TargetBonusOverride]           DECIMAL(18,2)   NULL,
        [IsTargetBonusEnabledOverride]  BIT             NULL,

        [CreatedDate]                   DATETIME2       NOT NULL CONSTRAINT [DF_SalaryEmployee_CreatedDate] DEFAULT (SYSDATETIME()),

        CONSTRAINT [PK_SalaryEmployee] PRIMARY KEY CLUSTERED ([EmployeeId]),
        CONSTRAINT [CK_SalaryEmployee_Status] CHECK ([Status] IN ('Active', 'Inactive'))
    );
END;
GO

--------------------------------------------------------------------------------
-- 3. z_tb_SalaryHoliday  (mercantile holiday calendar)
--------------------------------------------------------------------------------
IF OBJECT_ID(N'[dbo].[z_tb_SalaryHoliday]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[z_tb_SalaryHoliday] (
        [HolidayId]     INT             IDENTITY(1,1) NOT NULL,
        [HolidayDate]   DATE            NOT NULL,
        [Description]   NVARCHAR(200)   NULL,
        [CreatedDate]   DATETIME2       NOT NULL CONSTRAINT [DF_SalaryHoliday_CreatedDate] DEFAULT (SYSDATETIME()),

        CONSTRAINT [PK_SalaryHoliday] PRIMARY KEY CLUSTERED ([HolidayId]),
        CONSTRAINT [UQ_SalaryHoliday_HolidayDate] UNIQUE ([HolidayDate])
    );
END;
GO

--------------------------------------------------------------------------------
-- 4. z_tb_SalaryAttendance  (one row per employee per day)
--------------------------------------------------------------------------------
IF OBJECT_ID(N'[dbo].[z_tb_SalaryAttendance]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[z_tb_SalaryAttendance] (
        [AttendanceId]          INT             IDENTITY(1,1) NOT NULL,
        [EmployeeId]            INT             NOT NULL,
        [AttendanceDate]        DATE            NOT NULL,
        [IsPresent]             BIT             NOT NULL CONSTRAINT [DF_SalaryAttendance_IsPresent] DEFAULT (0),
        [OtHours]               DECIMAL(4,1)    NOT NULL CONSTRAINT [DF_SalaryAttendance_OtHours] DEFAULT (0),
        [IsMercantileHoliday]   BIT             NOT NULL CONSTRAINT [DF_SalaryAttendance_IsMercantileHoliday] DEFAULT (0),
        [CreatedDate]           DATETIME2       NOT NULL CONSTRAINT [DF_SalaryAttendance_CreatedDate] DEFAULT (SYSDATETIME()),

        CONSTRAINT [PK_SalaryAttendance] PRIMARY KEY CLUSTERED ([AttendanceId]),
        CONSTRAINT [UQ_SalaryAttendance_Employee_Date] UNIQUE ([EmployeeId], [AttendanceDate]),
        CONSTRAINT [FK_SalaryAttendance_Employee] FOREIGN KEY ([EmployeeId])
            REFERENCES [dbo].[z_tb_SalaryEmployee] ([EmployeeId])
    );

    CREATE INDEX [IX_SalaryAttendance_AttendanceDate] ON [dbo].[z_tb_SalaryAttendance] ([AttendanceDate]);
END;
GO

--------------------------------------------------------------------------------
-- 5. z_tb_SalaryAdvance  (advance payments per employee)
--------------------------------------------------------------------------------
IF OBJECT_ID(N'[dbo].[z_tb_SalaryAdvance]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[z_tb_SalaryAdvance] (
        [AdvanceId]     INT             IDENTITY(1,1) NOT NULL,
        [EmployeeId]    INT             NOT NULL,
        [AdvanceDate]   DATE            NOT NULL,
        [Amount]        DECIMAL(18,2)   NOT NULL,
        [Remarks]       NVARCHAR(200)   NULL,
        [CreatedDate]   DATETIME2       NOT NULL CONSTRAINT [DF_SalaryAdvance_CreatedDate] DEFAULT (SYSDATETIME()),

        CONSTRAINT [PK_SalaryAdvance] PRIMARY KEY CLUSTERED ([AdvanceId]),
        CONSTRAINT [FK_SalaryAdvance_Employee] FOREIGN KEY ([EmployeeId])
            REFERENCES [dbo].[z_tb_SalaryEmployee] ([EmployeeId])
    );

    CREATE INDEX [IX_SalaryAdvance_Employee_Date] ON [dbo].[z_tb_SalaryAdvance] ([EmployeeId], [AdvanceDate]);
END;
GO

--------------------------------------------------------------------------------
-- 6. z_tb_SalaryPayslip  (computed/generated payslip snapshot per employee/month)
--------------------------------------------------------------------------------
IF OBJECT_ID(N'[dbo].[z_tb_SalaryPayslip]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[z_tb_SalaryPayslip] (
        [PayslipId]         INT             IDENTITY(1,1) NOT NULL,
        [EmployeeId]        INT             NOT NULL,
        [PayMonth]          TINYINT         NOT NULL,
        [PayYear]           SMALLINT        NOT NULL,

        [TotalDaysInMonth]  TINYINT         NOT NULL,
        [DaysPresent]       TINYINT         NOT NULL,
        [BasicEarned]       DECIMAL(18,2)   NOT NULL,

        [OtHours]           DECIMAL(6,1)    NOT NULL CONSTRAINT [DF_SalaryPayslip_OtHours] DEFAULT (0),
        [OtAmount]          DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryPayslip_OtAmount] DEFAULT (0),

        [ByShop]            DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryPayslip_ByShop] DEFAULT (0),
        [AttendanceBonus]   DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryPayslip_AttendanceBonus] DEFAULT (0),

        [MhCount]           TINYINT         NOT NULL CONSTRAINT [DF_SalaryPayslip_MhCount] DEFAULT (0),
        [MhAmount]          DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryPayslip_MhAmount] DEFAULT (0),
        [MhOtHours]         DECIMAL(6,1)    NOT NULL CONSTRAINT [DF_SalaryPayslip_MhOtHours] DEFAULT (0),
        [MhOtAmount]        DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryPayslip_MhOtAmount] DEFAULT (0),

        [TargetBonus]       DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryPayslip_TargetBonus] DEFAULT (0),
        [AdvanceDeduction]  DECIMAL(18,2)   NOT NULL CONSTRAINT [DF_SalaryPayslip_AdvanceDeduction] DEFAULT (0),

        [NetSalary]         DECIMAL(18,2)   NOT NULL,

        [Status]            NVARCHAR(20)    NOT NULL CONSTRAINT [DF_SalaryPayslip_Status] DEFAULT ('Draft'),
        [GeneratedDate]      DATETIME2       NOT NULL CONSTRAINT [DF_SalaryPayslip_GeneratedDate] DEFAULT (SYSDATETIME()),

        CONSTRAINT [PK_SalaryPayslip] PRIMARY KEY CLUSTERED ([PayslipId]),
        CONSTRAINT [UQ_SalaryPayslip_Employee_Month_Year] UNIQUE ([EmployeeId], [PayMonth], [PayYear]),
        CONSTRAINT [FK_SalaryPayslip_Employee] FOREIGN KEY ([EmployeeId])
            REFERENCES [dbo].[z_tb_SalaryEmployee] ([EmployeeId]),
        CONSTRAINT [CK_SalaryPayslip_Status] CHECK ([Status] IN ('Draft', 'Final')),
        CONSTRAINT [CK_SalaryPayslip_PayMonth] CHECK ([PayMonth] BETWEEN 1 AND 12)
    );
END;
GO
