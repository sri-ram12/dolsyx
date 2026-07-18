import nodemailer from "nodemailer";
import dns from "dns";

// Prefer IPv4 to resolve SMTP ENETUNREACH errors on cloud container platforms
if (typeof dns.setDefaultResultOrder === "function") {
  dns.setDefaultResultOrder("ipv4first");
}

export interface EmailOptions {
  to: string;
  subject: string;
  name: string;
  otp: string;
}

class EmailService {
  private transporter: nodemailer.Transporter | null = null;

  constructor() {
    this.verifyConnection();
  }

  private async verifyConnection() {
    setTimeout(async () => {
      try {
        const transporter = await this.getTransporter();
        if (transporter && typeof transporter.verify === "function") {
          await transporter.verify();
          console.log("[EmailService] SMTP Connection verified successfully.");
        }
      } catch (err) {
        console.error("[EmailService] SMTP Connection verification failed:", err);
      }
    }, 1000);
  }

  private async getTransporter(): Promise<nodemailer.Transporter> {
    if (this.transporter) {
      return this.transporter;
    }

    const host = process.env.SMTP_HOST || "smtp.gmail.com";
    const port = parseInt(process.env.SMTP_PORT || "465");
    const user = process.env.SMTP_USER || "chandusonti70@gmail.com";
    const pass = process.env.SMTP_PASS;

    if (pass) {
      console.log(`[EmailService] Initializing SMTP transporter with host=${host}, user=${user}`);
      const transportConfig: any = host === "smtp.gmail.com" || user.endsWith("@gmail.com")
        ? {
            service: "gmail",
            auth: {
              user,
              pass,
            },
            connectionTimeout: 3000,
            greetingTimeout: 3000,
            socketTimeout: 3000,
          }
        : {
            host,
            port,
            secure: port === 465,
            auth: {
              user,
              pass,
            },
            connectionTimeout: 3000,
            greetingTimeout: 3000,
            socketTimeout: 3000,
          };
      this.transporter = nodemailer.createTransport(transportConfig);
      return this.transporter;
    }

    // Fallback: If no password is provided in ENV, we auto-create an Ethereal test SMTP account
    console.log("[EmailService] No SMTP password config found in environment variables. Setting up Ethereal test mailer...");
    try {
      const testAccount = await nodemailer.createTestAccount();
      console.log(`[EmailService] Created Ethereal test account: ${testAccount.user}`);
      this.transporter = nodemailer.createTransport({
        host: "smtp.ethereal.email",
        port: 587,
        secure: false,
        auth: {
          user: testAccount.user,
          pass: testAccount.pass,
        },
      });
      return this.transporter;
    } catch (err) {
      console.error("[EmailService] Failed to create Ethereal test account. Initializing console-only transport.", err);
      // Stub transporter that does nothing
      this.transporter = {
        sendMail: async (mailOptions: any) => {
          console.log("[EmailService] [STUB] Ethereal creator failed. Mail would be sent to:", mailOptions.to);
          return { messageId: "stub-id" };
        }
      } as any;
      return this.transporter!;
    }
  }

  public async sendOtpEmail(options: EmailOptions): Promise<boolean> {
    try {
      const transporter = await this.getTransporter();
      const fromEmail = process.env.SMTP_FROM || `"DOLSYX Team" <${process.env.SMTP_USER || "chandusonti70@gmail.com"}>`;

      const htmlContent = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Login Verification Code</title>
  <style>
    body {
      font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
      background-color: #0b0716;
      margin: 0;
      padding: 0;
      -webkit-font-smoothing: antialiased;
      color: #f3f4f6;
    }
    .wrapper {
      width: 100%;
      background-color: #0b0716;
      padding: 40px 0;
    }
    .container {
      max-width: 560px;
      margin: 0 auto;
      background: #120d24;
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 20px;
      overflow: hidden;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5);
    }
    .header {
      background: linear-gradient(135deg, #7c3aed, #a855f7);
      padding: 30px;
      text-align: center;
    }
    .header h1 {
      margin: 0;
      color: #ffffff;
      font-size: 28px;
      font-weight: 800;
      letter-spacing: 2px;
    }
    .content {
      padding: 40px 30px;
    }
    .greeting {
      font-size: 18px;
      color: #f3f4f6;
      font-weight: 600;
      margin-bottom: 20px;
    }
    .body-text {
      font-size: 15px;
      color: #9ca3af;
      line-height: 1.6;
      margin-bottom: 30px;
    }
    .otp-container {
      background: rgba(255, 255, 255, 0.04);
      border: 1px dashed rgba(168, 85, 247, 0.4);
      border-radius: 12px;
      padding: 24px;
      text-align: center;
      margin: 30px 0;
    }
    .otp-code {
      font-size: 42px;
      font-weight: 800;
      letter-spacing: 8px;
      color: #c084fc;
      margin: 0;
      font-family: 'Courier New', Courier, monospace;
    }
    .expiry {
      font-size: 12px;
      color: #a855f7;
      font-weight: bold;
      margin-top: 10px;
    }
    .security-notice {
      font-size: 13px;
      color: #6b7280;
      border-top: 1px solid rgba(255, 255, 255, 0.06);
      padding-top: 20px;
      margin-top: 30px;
      line-height: 1.5;
    }
    .footer {
      background: #090514;
      padding: 20px 30px;
      text-align: center;
      font-size: 12px;
      color: #4b5563;
      border-top: 1px solid rgba(255, 255, 255, 0.05);
    }
    .footer a {
      color: #7c3aed;
      text-decoration: none;
    }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="container">
      <div class="header">
        <h1>DOLSYX</h1>
      </div>
      <div class="content">
        <div class="greeting">Hello ${options.name},</div>
        <div class="body-text">
          Use the following verification code to secure your access to DOLSYX. This code is valid for 5 minutes and can only be used once.
        </div>
        <div class="otp-container">
          <div class="otp-code">${options.otp}</div>
          <div class="expiry">Expires in 5 minutes</div>
        </div>
        <div class="security-notice">
          <strong>Security Notice:</strong> If you did not initiate this login request, please disregard this email. Never share this code with anyone. Our support team will never ask for your verification code.
        </div>
      </div>
      <div class="footer">
        &copy; 2026 DOLSYX Messenger Team. All rights reserved.<br>
        If you need assistance, please contact our <a href="mailto:support@dolsyx.com">Support Team</a>.
      </div>
    </div>
  </div>
</body>
</html>
      `;

      const info = await transporter.sendMail({
        from: fromEmail,
        to: options.to,
        subject: options.subject,
        html: htmlContent,
        text: `Hello ${options.name},\n\nYour verification code is: ${options.otp}\n\nThis code expires in 5 minutes.\n\nIf you did not request this login, please ignore this email.\n\nRegards,\nDOLSYX Messenger Team`,
      });

      console.log(`[EmailService] OTP email sent to ${options.to}. MessageID: ${info.messageId}`);
      
      // If Ethereal test transport, log the preview URL
      const previewUrl = nodemailer.getTestMessageUrl(info);
      if (previewUrl) {
        console.log(`\n==========================================`);
        console.log(`[EmailService] [Ethereal Preview URL]`);
        console.log(`${previewUrl}`);
        console.log(`==========================================\n`);
      }

      return true;
    } catch (err) {
      console.error("[EmailService] Error sending email:", err);
      return false;
    }
  }
}

export const emailService = new EmailService();
