using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    public class SalaryContext : DbContext
    {
        public SalaryContext(DbContextOptions<SalaryContext> options)
            : base(options)
        {
        }

        public DbSet<SalaryConfig> SalaryConfigs { get; set; }
        public DbSet<SalaryEmployee> SalaryEmployees { get; set; }
        public DbSet<SalaryHoliday> SalaryHolidays { get; set; }
        public DbSet<SalaryAttendance> SalaryAttendances { get; set; }
        public DbSet<SalaryAdvance> SalaryAdvances { get; set; }
        public DbSet<SalaryPayslip> SalaryPayslips { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<SalaryConfig>().ToTable("z_tb_SalaryConfig");
            modelBuilder.Entity<SalaryEmployee>().ToTable("z_tb_SalaryEmployee");
            modelBuilder.Entity<SalaryHoliday>().ToTable("z_tb_SalaryHoliday");
            modelBuilder.Entity<SalaryAttendance>().ToTable("z_tb_SalaryAttendance");
            modelBuilder.Entity<SalaryAdvance>().ToTable("z_tb_SalaryAdvance");
            modelBuilder.Entity<SalaryPayslip>().ToTable("z_tb_SalaryPayslip");

            modelBuilder.Entity<SalaryHoliday>()
                .HasIndex(h => h.HolidayDate)
                .IsUnique();

            modelBuilder.Entity<SalaryAttendance>()
                .HasIndex(a => new { a.EmployeeId, a.AttendanceDate })
                .IsUnique();

            modelBuilder.Entity<SalaryAdvance>()
                .HasIndex(a => new { a.EmployeeId, a.AdvanceDate });

            modelBuilder.Entity<SalaryPayslip>()
                .HasIndex(p => new { p.EmployeeId, p.PayMonth, p.PayYear })
                .IsUnique();

            // z_tb_SalaryPayslip stores these as tinyint/smallint; without an explicit
            // conversion EF reads them via SqlDataReader.GetInt32() and throws
            // InvalidCastException (Byte -> Int32) once rows actually exist to read back.
            modelBuilder.Entity<SalaryPayslip>().Property(p => p.PayMonth).HasConversion<byte>();
            modelBuilder.Entity<SalaryPayslip>().Property(p => p.PayYear).HasConversion<short>();
            modelBuilder.Entity<SalaryPayslip>().Property(p => p.TotalDaysInMonth).HasConversion<byte>();
            modelBuilder.Entity<SalaryPayslip>().Property(p => p.DaysPresent).HasConversion<byte>();
            modelBuilder.Entity<SalaryPayslip>().Property(p => p.MhCount).HasConversion<byte>();

            base.OnModelCreating(modelBuilder);
        }
    }
}
