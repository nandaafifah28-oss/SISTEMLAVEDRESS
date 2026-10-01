(function () {
  const supabase = window.lave.supabase;
  const FAIL_MESSAGE = 'Data dress gagal diperbarui. Silakan periksa kembali data atau hak akses.';

  function currentRole() {
    return String(
      window.lave.profile?.profile_role || window.lave.profile?.role || ''
    ).toLowerCase();
  }

  function canEditDressMaster() {
    return ['admin', 'staff'].includes(currentRole());
  }

  function rlsDenied(error) {
    const text = `${error?.message || ''} ${error?.code || ''} ${error?.details || ''}`.toLowerCase();
    return error?.code === '42501' ||
      text.includes('row-level security') ||
      text.includes('permission denied');
  }

  function buildDressMasterPayload(input) {
    const name = String(input?.name || '').trim();
    if (!name) return { error: 'Nama dress wajib diisi.' };

    const categoryId = Number(input?.category_id);
    if (!Number.isInteger(categoryId) || categoryId <= 0) {
      return { error: 'Kategori wajib diisi.' };
    }

    const purchaseRaw = input?.purchase_price;
    const rentalRaw = input?.rental_price;

    if (
      purchaseRaw === '' ||
      purchaseRaw == null ||
      rentalRaw === '' ||
      rentalRaw == null
    ) {
      return { error: 'Tolong masukkan harga yang valid.' };
    }

    const purchase_price = Number(purchaseRaw);
    const rental_price = Number(rentalRaw);

    if (!Number.isFinite(purchase_price) || !Number.isFinite(rental_price)) {
      return { error: 'Tolong masukkan harga yang valid.' };
    }

    if (purchase_price < 0 || rental_price < 0) {
      return { error: 'Harga tidak boleh negatif.' };
    }

    const supplierRaw = input?.supplier_id;
    let supplier_id = null;

    if (supplierRaw !== '' && supplierRaw != null) {
      supplier_id = Number(supplierRaw);
      if (!Number.isInteger(supplier_id) || supplier_id <= 0) {
        return { error: 'Supplier tidak valid.' };
      }
    }

    return {
      payload: {
        name,
        category_id: categoryId,
        purchase_price,
        rental_price,
        supplier_id,
        condition: String(input?.condition || 'Good'),
        description: String(input?.description || '').trim() || null
      }
    };
  }

  async function uploadDressPhoto(file, existingUrl) {
    if (!file) {
      return { photo_url: existingUrl || null, uploadedPath: null };
    }

    if (!file.type.startsWith('image/') || file.size > 5 * 1024 * 1024) {
      return { error: 'Pilih file gambar berukuran maksimal 5 MB.' };
    }

    const extension =
      file.name.split('.').pop().toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';

    const path = `public/${crypto.randomUUID()}.${extension}`;
    const storage = supabase.storage.from('dress-photos');

    const upload = await storage.upload(path, file, {
      contentType: file.type,
      upsert: false
    });

    if (upload.error) return { error: upload.error.message };

    return {
      photo_url: storage.getPublicUrl(upload.data.path).data.publicUrl,
      uploadedPath: upload.data.path
    };
  }

  async function updateDress(dressId, fields, photoFile, extra = {}) {
    const id = Number(dressId);

    if (!Number.isInteger(id) || id <= 0) {
      const error = {
        message: 'Dress tidak ditemukan.',
        code: 'DRESS_ID_MISSING'
      };
      console.error('Update dress error:', error);
      return { error };
    }

    const built = buildDressMasterPayload(fields);

    if (built.error) {
      const error = {
        message: built.error,
        code: 'VALIDATION'
      };
      console.error('Update dress error:', error);
      return { error };
    }

    const existing = await supabase
      .from('dresses')
      .select('id, photo_url, dress_code')
      .eq('id', id)
      .maybeSingle();

    if (existing.error) {
      console.error('Update dress error:', existing.error);
      return { error: existing.error };
    }

    if (!existing.data) {
      const error = {
        message: 'Dress tidak ditemukan.',
        code: 'DRESS_NOT_FOUND'
      };
      console.error('Update dress error:', error);
      return { error };
    }

    const photo = await uploadDressPhoto(photoFile, existing.data.photo_url);

    if (photo.error) {
      const error = {
        message: photo.error,
        code: 'PHOTO_UPLOAD'
      };
      console.error('Update dress error:', error);
      return { error };
    }

    const payload = {
      ...built.payload,
      photo_url: photo.photo_url
    };

    if (Object.prototype.hasOwnProperty.call(extra, 'is_active')) {
      payload.is_active = extra.is_active !== false;
      payload.status = payload.is_active ? 'Available' : 'Not Available';
    }

    delete payload.id;
    delete payload.dress_code;
    delete payload.created_at;
    delete payload.updated_at;

    const result = await supabase
      .from('dresses')
      .update(payload)
      .eq('id', id)
      .select('id')
      .maybeSingle();

    if (result.error) {
      if (photo.uploadedPath) {
        await supabase.storage.from('dress-photos').remove([photo.uploadedPath]);
      }

      console.error('Update dress error:', result.error);

      const message = rlsDenied(result.error)
        ? FAIL_MESSAGE
        : (result.error.message || FAIL_MESSAGE);

      return {
        error: {
          ...result.error,
          message
        }
      };
    }

    if (!result.data) {
      if (photo.uploadedPath) {
        await supabase.storage.from('dress-photos').remove([photo.uploadedPath]);
      }

      const error = {
        message: FAIL_MESSAGE,
        code: 'NO_ROW_UPDATED'
      };

      console.error('Update dress error:', error);
      return { error };
    }

    return { data: result.data };
  }

  window.lave.buildDressMasterPayload = buildDressMasterPayload;
  window.lave.uploadDressPhoto = uploadDressPhoto;
  window.lave.updateDress = updateDress;
  window.lave.canEditDressMaster = canEditDressMaster;
}());