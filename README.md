# LAVÉ Dress Rental & Accounting System

Frontend: HTML + CSS + JavaScript. Backend: Supabase PostgreSQL.

## Setup
1. Buat project Supabase.
2. Jalankan SQL secara berurutan: 01_schema.sql, 02_seed.sql, 03_functions.sql, 04_triggers.sql, 05_views.sql, 06_integration_fix.sql, 07_trigger_hotfix.sql, 09_accounting_reporting.sql, 10_settings_security_inventory.sql, 11_auth_rls_hotfix.sql, 12_return_penalty_integration.sql, 13_capital_contribution.sql, 14_purchase_inventory_integration.sql, 15_accounting_integrity_hardening.sql, 16_purchase_transaction_rpc.sql, 17_capital_view_repair.sql, 18_atomic_payment_flows.sql, 19_supplier_notes.sql, 20_capital_posting_rpc.sql, 21_capital_role_access.sql, 22_settings_rls_repair.sql, 23_dress_model_merge_prepare.sql, 24_dress_variant_schema_backfill.sql, 25_dress_variant_transaction_flows.sql, 26_dress_photo_storage.sql, 27_purchase_dress_id_ambiguity_fix.sql, 28_deposit_return_accounting.sql, 29_dress_variant_color.sql, 30_variant_inventory_status.sql, 31_purchase_payable_integrity.sql, 32_dress_physical_units.sql, 33_unit_purchase_rental_flows.sql, 34_unit_return_inventory_flows.sql, 35_fix_v_dress_inventory.sql, lalu 36_public_access.sql.
3. Isi URL dan publishable/anon key pada frontend/js/config.js.
4. Jalankan frontend dengan Live Server di VS Code dan buka frontend/html/index.html.
5. Jangan pernah memasukkan service_role/secret key ke frontend.

## GitHub Pages
Workflow `.github/workflows/pages.yml` menerbitkan folder `frontend` setiap ada push ke branch `main`. Pada repository GitHub, buka **Settings > Pages** dan pilih **GitHub Actions** sebagai source. Setelah perubahan frontend dan workflow di-commit dan di-push, situs tersedia di URL Pages repository dan root situs langsung menuju dashboard tanpa halaman login. Repository harus public agar pengunjung dapat membuka kode/situs tanpa masuk ke GitHub; pengaturan visibility repository tidak bisa diubah dari file aplikasi.

Untuk koneksi data tanpa login, jalankan migration `backend/database/36_public_access.sql` pada project Supabase yang URL-nya sedang dipakai di `frontend/js/config.js`. Tanpa migration tersebut, UI tetap terbuka tetapi request data akan ditolak. Migration itu membuka data dan operasi database kepada publik; jangan gunakan untuk data privat/produksi.

**Peringatan keamanan:** Migration 36 menonaktifkan RLS dan memberi role `anon` akses baca/tulis serta eksekusi RPC pada seluruh schema `public`. Siapa pun yang mengetahui URL aplikasi dapat membaca, mengubah, atau menghapus data pelanggan dan akuntansi. Gunakan hanya jika database memang sengaja dipublikasikan; jangan gunakan untuk data privat atau produksi.

## Catatan
- Master Dress adalah satu-satunya tempat membuat dan mengedit dress. Persediaan hanya membaca ketersediaan dan riwayat movement.
- Login Supabase Auth tidak digunakan; akses aplikasi memakai publishable/anon key dan database dibuka oleh migration 36.
- Migration 10 membuat settings, audit log, sequence configuration, movement otomatis, dan RLS. Buat baris `app_users` untuk setiap user Auth agar role `admin`, `staff`, `accounting`, atau `owner` diterapkan.
- Migration 11 membuat profile `app_users` otomatis setelah login pertama, memperbaiki policy `accounts`/kategori, dan mencabut akses langsung ke PostgreSQL sequence.
- Migration 12 mengunci satu return per rental dan memproses return, denda keterlambatan, kerusakan, pembayaran denda, perubahan status dress, dan status rental dalam satu RPC database.
- Migration 13 menambahkan setoran modal pemilik sebagai transaksi ekuitas atomic (`MOD-0001`), jurnal kas/modal, view modal, dan klasifikasi arus kas pendanaan.
- Migration 14 mencatat `PURCHASE_IN` dari purchase detail dan melengkapi movement `RENTAL_CANCEL` saat rental dibatalkan.
- Migration 15 menambahkan reversal modal dan deferred journal-balance validation.
- Migration 16 membuat Purchase atomic melalui RPC sehingga Dress, Purchase, Detail, movement, dan journal rollback bersama jika salah satu langkah gagal.
- Migration 17 memperbaiki view canonical `v_capital_contributions`, memberikan grant read, dan memuat ulang schema cache PostgREST.
- Migration 18 membuat payment rental dan expense atomic dengan validasi outstanding balance dan posting journal dari database.
- Migration 19 menambahkan catatan supplier nullable tanpa mengubah relasi supplier existing.
- Migration 20 memindahkan posting modal ke RPC authenticated dengan `auth.uid()`, role validation, dan policy `created_by`.
- Migration 21 mengizinkan role operasional `staff` memakai RPC modal yang tetap tervalidasi, tanpa membuka insert langsung atau menonaktifkan RLS.
- Sebelum migration 23-25, backup database dan hentikan penulisan transaksi. Migration 23 membuat `dress_model_merge_map`; tinjau query audit di file tersebut dan masukkan hanya pasangan model duplikat yang sudah diverifikasi, dengan `source_dress_id` diarahkan ke `target_dress_id` canonical. Kesamaan nama saja bukan bukti model sama. Jangan hard-delete master sumber; migration 24 mengalihkan referensi transaksi/movement dan menandai master sumber nonaktif.
- Migration 24 mempertahankan stok yang sebelumnya terlihat: setiap baris `dresses` dihitung sebagai satu unit per ukuran/status lama. `purchase_details.quantity` historis tidak dijumlahkan karena alur lama tidak menggunakannya untuk menghitung stok; tinjau query audit migration 23 dan cocokkan stok fisik sebelum migration. Baris tanpa ukuran dimigrasikan ke `UNKNOWN` dan tidak dapat disewakan. Lakukan stocktake, lalu gunakan pembelian untuk memasukkan ukuran/stok yang sudah terverifikasi.
- Jalankan migration 24 dan 25 dalam satu jendela maintenance, kemudian deploy frontend. Migration 25 mengganti RPC pembelian/rental/return dan mengunci write langsung ke detail; jangan gunakan frontend lama setelah migration 25. Jurnal lama tidak dihapus/ditulis ulang, dan pembelian baru tetap memicu jurnal melalui trigger purchase yang sudah ada.
- Migration 26 membuat bucket publik `dress-photos` untuk menampilkan foto, dengan upload/delete terbatas ke folder user terautentikasi ber-role `admin`/`staff`; sesuaikan kebijakan bucket jika project membutuhkan foto privat.
- Migration 27 memperbaiki ambiguitas kolom `dress_id` pada RPC pembelian tanpa mengubah bentuk respons RPC.
- Migration 28 mencatat deposit baru sebagai liabilitas, menyiapkan saldo pembuka untuk deposit rental yang masih aktif, mengalokasikan deposit saat return, dan mengamankan RPC pembayaran. Deposit historis pada rental yang sudah selesai tidak ditebak atau ditulis ulang.
- Migration 29 menambahkan warna pada varian. Stok gabungan dari model beda warna yang sudah dikonsolidasikan migration 24 ditandai `UNVERIFIED`; cocokkan fisik lalu gunakan aksi Stocktake Warna sebelum varian tersebut disewakan.
- Migration 30 memisahkan jumlah tersedia, disewa, laundry, repair, tidak layak, dan belum terklasifikasi per varian, serta mencatat perubahan status dan rekonsiliasi sebagai movement.
- Migration 31 membuat `v_purchase_payables` hanya menampilkan saldo positif dan memindahkan pembayaran utang ke RPC atomik. Deploy frontend setelah migration 28-31 selesai.
- Migration 32 membuat `dress_units`, menjaga counter varian dan status legacy saat backfill, serta mengaitkan unit ke rental aktif yang dapat dipetakan. Kode `UNIT-########` adalah ID fisik internal; cocokkan/tempelkan label pada barang saat stocktake.
- Migration 33 membuat unit baru per qty pembelian, memilih dan mengunci satu unit `Available` saat rental, serta mencatat purchase/rental movement per unit.
- Migration 34 mengubah return, pembatalan, edit status, stocktake warna, dan view inventory agar memakai unit. Jalankan 32-35 dalam maintenance window dan deploy frontend hanya setelah semuanya sukses.
- Migration 35 membuat ulang `v_dress_inventory` tanpa alias CTE `counts`, agar query sample kolom `condition` tidak gagal dengan `missing FROM-clause entry for table "counts"`. Jika 34 sudah dijalankan, cukup jalankan 35.
- Unit legacy dibuat dari counter varian dengan kode internal `UNIT-########`; cocokkan kode dan tempel label pada unit fisik sebelum operasi stocktake. Rental aktif yang tidak bisa dipetakan atau counter yang tidak seimbang akan membatalkan migration 32.
- Halaman Jurnal Umum terpisah telah dihapus; tinjau detail jurnal per akun melalui Buku Besar. Data dan proses posting jurnal tetap digunakan oleh akuntansi dan laporan.
- Uji transaksi setelah seluruh migration aktif: Dress -> Purchase -> Rental -> Return -> Journal, lalu cek RLS dengan akun staff dan admin.
