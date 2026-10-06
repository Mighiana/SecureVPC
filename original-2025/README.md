# Original console build (24 August 2025)

These files are the evidence from the original SecureVPC project, which was built by hand in the
AWS Management Console. They are the contents of the first commit in this repository
([`469a821`](https://github.com/Mighiana/SecureVPC/commit/469a821)). Files were only moved into
this folder; their contents are unchanged.

`readme.md.txt` holds the original setup notes. Screenshots, in the order they were taken:

| Time  | File | Shows |
|-------|------|-------|
| 11:56 | [115647](<Screenshot 2025-08-24 115647.png>) | VPC `securevpc-usman`, 10.0.0.0/16 |
| 12:10 | [121048](<Screenshot 2025-08-24 121048.png>) | Public (10.0.1.0/24) and private (10.0.2.0/24) subnets |
| 12:13 | [121315](<Screenshot 2025-08-24 121315.png>) | Internet Gateway attached |
| 12:28 | [122834](<Screenshot 2025-08-24 122834.png>) | NAT Gateway in the public subnet |
| 12:30 | [123028](<Screenshot 2025-08-24 123028.png>) | Private route table: 0.0.0.0/0 → NAT Gateway |
| 12:43 | [124314](<Screenshot 2025-08-24 124314.png>) | Bastion host launching |
| 13:05 | [130519](<Screenshot 2025-08-24 130519.png>) | Bastion and web server running |
| 13:21 | [132104](<Screenshot 2025-08-24 132104.png>) | SSH workstation → bastion → web server |
| 13:21 | [132118](<Screenshot 2025-08-24 132118.png>) | Shell on the private web server (10.0.2.164) |
| 13:21 | [132151](<Screenshot 2025-08-24 132151.png>) | `curl` from bastion returns `<h1>Secure Web Server</h1>` |
| 13:24 | [132403](<Screenshot 2025-08-24 132403.png>) | `curl` to the private IP from outside the VPC fails |
| 14:49 | [144917](<Screenshot 2025-08-24 144917.png>) | VPC Flow Log (ALL) → CloudWatch Logs created |
| 17:22 | [172200](<Screenshot 2025-08-24 172200.png>) | Flow Log `SecureVPC-FlowLogs` active |

The values in these files (IDs, IPs, the key name, the instance type) describe a deployment that
was later deleted. Don't reuse them. The Terraform in [`../terraform`](../terraform) generates
fresh values.
