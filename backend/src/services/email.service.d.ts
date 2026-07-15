export interface EmailOptions {
    to: string;
    subject: string;
    name: string;
    otp: string;
}
declare class EmailService {
    private transporter;
    constructor();
    private verifyConnection;
    private getTransporter;
    sendOtpEmail(options: EmailOptions): Promise<boolean>;
}
export declare const emailService: EmailService;
export {};
//# sourceMappingURL=email.service.d.ts.map