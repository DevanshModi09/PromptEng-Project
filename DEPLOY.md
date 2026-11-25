# Deploying CampusCrew on EC2

## Option A — nginx directly on the instance (simplest)

### 1. Launch an EC2 instance
- **AMI**: Amazon Linux 2023 or Ubuntu 22.04/24.04 (free-tier `t2.micro` or `t3.micro` is fine)
- **Security group**: open inbound TCP **port 80** (HTTP) from `0.0.0.0/0`
- Download your `.pem` key

### 2. Copy the project to the instance
```bash
# From your laptop – replace <KEY> and <HOST>
scp -i <KEY>.pem -r /Users/dev/Desktop/Projects/PromptEng/CampusCrew_code ec2-user@<HOST>:~/campuscrew
# Ubuntu uses 'ubuntu' instead of 'ec2-user'
```

### 3. SSH in and run the setup script
```bash
ssh -i <KEY>.pem ec2-user@<HOST>
cd ~/campuscrew/deploy
bash setup.sh
```

The script **only reloads** nginx — it does not restart it or touch your existing SSL certificates or server blocks. It drops a new file at `/etc/nginx/conf.d/campuscrew.conf`.

**If you already have a server block on port 80** (e.g. for your domain with SSL), open `deploy/campuscrew.nginx.conf` and either:
- Change `server_name _;` to a subdomain like `crew.yourdomain.com`, or
- Skip the conf file and add `location /campuscrew { alias /var/www/campuscrew; try_files $uri /index.html; }` inside your existing server block manually.

Then run `sudo nginx -t && sudo systemctl reload nginx`.

Open `http://<EC2-PUBLIC-IP>` (or your subdomain) in your browser.

---

## Option B — Docker (if you prefer containers)

### On the EC2 instance
```bash
# Install Docker (Amazon Linux 2023)
sudo yum install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user
# Log out and back in, then:

cd ~/campuscrew
docker build -t campuscrew .
docker run -d --restart unless-stopped -p 80:80 campuscrew
```

Open `http://<EC2-PUBLIC-IP>`.

---

## Security group reminder
Make sure your EC2 security group has this inbound rule:

| Type | Protocol | Port | Source       |
|------|----------|------|--------------|
| HTTP | TCP      | 80   | 0.0.0.0/0    |

If you want HTTPS later, add port 443 and use `certbot` (Let's Encrypt) — but HTTP is fine for a demo tomorrow.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Browser shows "connection refused" | Check the security group port 80 rule |
| nginx fails to start | Run `sudo nginx -t` and check `/var/log/nginx/error.log` |
| Changes not showing | Run `sudo cp campuscrew_demo.html /var/www/campuscrew/index.html && sudo systemctl reload nginx` |
