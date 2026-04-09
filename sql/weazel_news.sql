CREATE TABLE IF NOT EXISTS weazel_journals (
  id INT AUTO_INCREMENT PRIMARY KEY,
  unique_id VARCHAR(32) NOT NULL UNIQUE,
  author VARCHAR(64) NOT NULL,
  publish_date DATETIME NOT NULL,
  image LONGTEXT NOT NULL,
  mime_type VARCHAR(32) NOT NULL,
  resolution VARCHAR(32) NOT NULL,
  filename VARCHAR(128) NOT NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'published',
  INDEX idx_weazel_journals_status_date (status, publish_date)
);

CREATE TABLE IF NOT EXISTS weazel_journal_purchases (
  id INT AUTO_INCREMENT PRIMARY KEY,
  journal_id INT NOT NULL,
  buyer_name VARCHAR(64) NOT NULL,
  purchase_date DATETIME NOT NULL,
  price INT NOT NULL,
  shop_name VARCHAR(128) NOT NULL,
  INDEX idx_weazel_journal_purchases_journal_id (journal_id),
  CONSTRAINT fk_weazel_journal_purchases_journal
    FOREIGN KEY (journal_id) REFERENCES weazel_journals(id)
    ON DELETE CASCADE
);
