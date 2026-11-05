# Amount entry and media access

All editable monetary values use the numeric mode of TenderField. Its decimal keypad is applied directly to the underlying native text field. A stored zero is shown as an empty field with its normal placeholder and clears on focus; entering 50 therefore yields 50 rather than 0.0050. Existing nonzero amounts are selected on focus for replacement. Merely displaying a placeholder does not change the ledger. Amount parsing and Save validation remain unchanged. This applies to accounts, cash, expenses, envelopes/monthly allocation, recurring payments, shopping, groceries, receipt item corrections and subscription notice review. Quantity controls remain numeric pickers/steppers.

CameraPicker is a permission gate shared by price-label scanning, receipts/bills and profile capture. Only a camera action mounts it. It checks AVCaptureDevice authorization, asks for video permission when undetermined, and creates UIImagePickerController only after authorization. Denied access shows Open Settings and Close; restricted and unavailable cameras have recovery explanations. Returning from Settings rechecks access. A Debug-only denied-state simulator fixture does not touch actual camera permission.

Photo and receipt uploads use Apple's system PhotosPicker, which grants the app access only to selected images. It does not need or request full photo-library permission. Files uses the existing security-scoped system picker. No camera, microphone or broad photo-library permission is requested on launch.

References: [Apple capture authorization](https://developer.apple.com/documentation/avfoundation/avcapturedevice/authorizationstatus(for:)), [Apple picker privacy](https://developer.apple.com/videos/play/wwdc2025/246/).
