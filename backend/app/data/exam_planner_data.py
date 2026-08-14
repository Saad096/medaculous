"""Static reference data for Exam Planner, ported from the legacy
src/data/examPlannerData.ts. EXAM_INFO is pure display metadata for the 16
supported exams; DEFAULT_BLUEPRINT is the single shared starter syllabus (9
specialties / 36 topics) seeded as each user's own editable copy on setup —
the legacy data was never actually exam-specific despite being keyed by
examId, so there is nothing to lose by sharing one blueprint.
"""

EXAM_INFO = [
    {"id": "plab1", "name": "PLAB 1", "full_name": "Professional and Linguistic Assessments Board Part 1", "region": "United Kingdom (GMC)", "description": "180 single-best-answer (SBA) clinical scenario questions for UK GMC registration.", "default_prep_weeks": 12},
    {"id": "plab2", "name": "PLAB 2", "full_name": "Professional and Linguistic Assessments Board Part 2", "region": "United Kingdom (GMC)", "description": "16-station Objective Structured Clinical Examination (OSCE) testing practical skills.", "default_prep_weeks": 10},
    {"id": "mrcp1", "name": "MRCP Part 1", "full_name": "Membership of the Royal Colleges of Physicians Part 1", "region": "United Kingdom & International", "description": "200 best-of-five questions on basic medical sciences and core clinical medicine.", "default_prep_weeks": 16},
    {"id": "mrcp2", "name": "MRCP Part 2", "full_name": "Membership of the Royal Colleges of Physicians Part 2 Written", "region": "United Kingdom & International", "description": "200 clinical scenario questions with image interpretation and complex management.", "default_prep_weeks": 14},
    {"id": "paces", "name": "MRCP PACES", "full_name": "Practical Assessment of Clinical Examination Skills", "region": "United Kingdom & International", "description": "5-station clinical exam with 8 patient encounters and communications stations.", "default_prep_weeks": 12},
    {"id": "usmle1", "name": "USMLE Step 1", "full_name": "United States Medical Licensing Examination Step 1", "region": "United States (NBME)", "description": "Assesses foundational science principles: Anatomy, Physiology, Pathology, Pharmacology.", "default_prep_weeks": 20},
    {"id": "usmle2ck", "name": "USMLE Step 2 CK", "full_name": "United States Medical Licensing Exam Step 2 Clinical Knowledge", "region": "United States (NBME)", "description": "Clinical medicine, diagnosis, management, patient safety, and disease prevention.", "default_prep_weeks": 16},
    {"id": "usmle3", "name": "USMLE Step 3", "full_name": "United States Medical Licensing Examination Step 3", "region": "United States (NBME)", "description": "Two-day exam testing patient management, ambulatory care, and CCS case simulations.", "default_prep_weeks": 12},
    {"id": "abim", "name": "ABIM Board", "full_name": "American Board of Internal Medicine Certification Exam", "region": "United States (ABIM)", "description": "Comprehensive internal medicine subspecialty knowledge assessment.", "default_prep_weeks": 20},
    {"id": "fcps", "name": "FCPS Part 1/2", "full_name": "Fellowship of College of Physicians and Surgeons", "region": "Pakistan & South Asia (CPSP)", "description": "Specialty board certification exam testing basic medical sciences and clinical medicine.", "default_prep_weeks": 16},
    {"id": "amc", "name": "AMC MCQ", "full_name": "Australian Medical Council MCQ Examination", "region": "Australia (AMC)", "description": "150 multiple choice questions evaluating clinical knowledge in medicine, surgery, pediatrics.", "default_prep_weeks": 16},
    {"id": "mccqe", "name": "MCCQE Part I", "full_name": "Medical Council of Canada Qualifying Examination Part I", "region": "Canada (MCC)", "description": "Computer-based test assessing clinical knowledge and decision-making for Canadian practice.", "default_prep_weeks": 14},
    {"id": "dha", "name": "DHA Exam", "full_name": "Dubai Health Authority General Practitioner / Specialist Licensing", "region": "United Arab Emirates (Dubai)", "description": "150 Prometric MCQs covering internal medicine, surgery, ob-gyn, pediatrics.", "default_prep_weeks": 8},
    {"id": "haad", "name": "HAAD / DOH", "full_name": "Department of Health Abu Dhabi Licensing Exam", "region": "United Arab Emirates (Abu Dhabi)", "description": "Standardized medical licensing exam for healthcare professionals in Abu Dhabi.", "default_prep_weeks": 8},
    {"id": "smle", "name": "SMLE", "full_name": "Saudi Medical Licensing Exam", "region": "Saudi Arabia (SCFHS)", "description": "300 MCQs testing foundational clinical medicine for medical practice in KSA.", "default_prep_weeks": 12},
    {"id": "prometric", "name": "Prometric Board", "full_name": "Gulf Prometric Medical Licensing Exam (OMSB/QCHP)", "region": "Oman, Qatar, Kuwait & Gulf States", "description": "Prometric medical licensure assessment for general practitioners and specialists.", "default_prep_weeks": 8},
    {"id": "custom", "name": "Custom Exam", "full_name": "Personalized Custom Medical Study Blueprint", "region": "Global Custom", "description": "Design your own custom syllabus, specialties, and topic schedule tailored to your goals.", "default_prep_weeks": 12},
]

DEFAULT_BLUEPRINT = [
    {
        "key": "cardiology", "title": "Cardiovascular Medicine", "icon": "Heart",
        "description": "Ischemic heart disease, heart failure, valvular disorders, arrhythmias, and hypertension.",
        "topics": [
            {"key": "card-1", "title": "Acute Coronary Syndromes (STEMI / NSTEMI)", "estimated_minutes": 60, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["Differentiate STEMI from NSTEMI/Unstable Angina via ECG & Troponin", "Identify emergency revascularization criteria (<120 mins PCI vs thrombolysis)", "Master dual antiplatelet (DAPT) and long-term secondary prevention guidelines"]},
            {"key": "card-2", "title": "Acute & Chronic Heart Failure", "estimated_minutes": 45, "difficulty": "moderate", "high_yield": True,
             "learning_objectives": ["Differentiate HFrEF vs HFpEF management pillars", "Recognize BNP thresholds and NYHA functional classifications", "Identify disease-modifying quadruplet therapy (ARNI, SGLT2i, Beta-Blocker, MRA)"]},
            {"key": "card-3", "title": "Arrhythmias & Cardiac Arrest Algorithms", "estimated_minutes": 50, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["Master ALS algorithm for Shockable vs Non-Shockable rhythms", "Calculate CHA2DS2-VASc and HAS-BLED scores for AF anticoagulation", "Differentiate narrow-complex vs wide-complex tachycardia management"]},
            {"key": "card-4", "title": "Valvular Heart Disease (AS, MR, AR, MS)", "estimated_minutes": 45, "difficulty": "moderate", "high_yield": False,
             "learning_objectives": ["Correlate cardiac auscultation findings with valve pathology", "Identify severe aortic stenosis symptoms (SAD: Syncope, Angina, Dyspnea)", "Master indications for TAVI vs surgical valve replacement"]},
            {"key": "card-5", "title": "Hypertension & Hypertensive Urgency/Emergency", "estimated_minutes": 35, "difficulty": "easy", "high_yield": False,
             "learning_objectives": ["Target blood pressure thresholds by age & renal comorbidities", "Differentiate hypertensive emergency vs urgency management goals"]},
        ],
    },
    {
        "key": "respiratory", "title": "Respiratory & Intensive Care", "icon": "Wind",
        "description": "Airway obstruction, parenchymal lung diseases, pulmonary circulation, and acute respiratory failure.",
        "topics": [
            {"key": "resp-1", "title": "Asthma & COPD Acute Exacerbations", "estimated_minutes": 50, "difficulty": "moderate", "high_yield": True,
             "learning_objectives": ["Recognize life-threatening asthma features (silent chest, normal PaCO2)", "Master oxygen therapy targets in COPD (88-92% vs 94-98%)", "NIV indications and contraindications in type II respiratory failure"]},
            {"key": "resp-2", "title": "Community & Hospital-Acquired Pneumonia", "estimated_minutes": 40, "difficulty": "easy", "high_yield": True,
             "learning_objectives": ["Apply CURB-65 / CRB-65 score for triage and admission", "Recognize atypical pneumonia features (Legionella, Mycoplasma)", "Empiric antibiotic selection guidelines"]},
            {"key": "resp-3", "title": "Pulmonary Embolism & Deep Vein Thrombosis", "estimated_minutes": 50, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["Calculate Wells score and PERC rule", "Interpret CTPA vs V/Q scan indications in renal impairment", "Thrombolysis criteria in massive hemodynamic unstable PE"]},
            {"key": "resp-4", "title": "Pleural Effusion & Pneumothorax Management", "estimated_minutes": 40, "difficulty": "moderate", "high_yield": False,
             "learning_objectives": ["Apply Light's criteria to distinguish Exudate vs Transudate", "Recognize tension pneumothorax signs and urgent needle decompression"]},
            {"key": "resp-5", "title": "Interstitial Lung Diseases & Sarcoidosis", "estimated_minutes": 45, "difficulty": "difficult", "high_yield": False,
             "learning_objectives": ["High-resolution CT (HRCT) honeycombing patterns in IPF", "Sarcoidosis staging, non-caseating granulomas, and bilateral hilar lymphadenopathy"]},
        ],
    },
    {
        "key": "endocrinology", "title": "Endocrinology & Metabolism", "icon": "Activity",
        "description": "Diabetes mellitus, thyroid, adrenal, pituitary, and calcium homeostasis.",
        "topics": [
            {"key": "endo-1", "title": "Diabetes Mellitus & Emergency Complications (DKA / HHS)", "estimated_minutes": 55, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["Diagnostic criteria differences between DKA and HHS", "Fluid resuscitation, IV insulin, and potassium replacement protocols", "HbA1c targets and modern GLP-1 / SGLT2i drug selection"]},
            {"key": "endo-2", "title": "Thyroid Disorders (Graves, Hashimoto, Thyroid Storm)", "estimated_minutes": 40, "difficulty": "moderate", "high_yield": True,
             "learning_objectives": ["Interpret complex Thyroid Function Test (TFT) patterns", "Management of Thyroid Storm (PTU, Beta-blockers, Steroids, Lugol's iodine)"]},
            {"key": "endo-3", "title": "Adrenal Insufficiency & Addisonian Crisis", "estimated_minutes": 45, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["Recognize Addisonian crisis (hypotension, hyponatremia, hyperkalemia)", "Immediate STAT IV Hydrocortisone & fluid resuscitation"]},
            {"key": "endo-4", "title": "Calcium & Electrolyte Derangements (Hyponatremia, SIADH)", "estimated_minutes": 50, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["Evaluation of Hypo/Hypernatremia and osmotic demyelination risk", "SIADH diagnostic criteria and fluid restriction management"]},
        ],
    },
    {
        "key": "gastroenterology", "title": "Gastroenterology & Hepatology", "icon": "Utensils",
        "description": "Upper and lower GI disorders, inflammatory bowel disease, liver cirrhosis, and biliary pathology.",
        "topics": [
            {"key": "gastro-1", "title": "Upper GI Bleeding & Variceal Hemorrhage", "estimated_minutes": 50, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["Apply Glasgow-Blatchford & Rockall risk stratification scores", "Medical management of variceal bleed (Terlipressin, prophylactic Abx, early EGD)"]},
            {"key": "gastro-2", "title": "Inflammatory Bowel Disease (Crohn's vs Ulcerative Colitis)", "estimated_minutes": 45, "difficulty": "moderate", "high_yield": True,
             "learning_objectives": ["Compare endoscopy & histological distinctions (skip lesions vs continuous)", "Acute severe ulcerative colitis management (IV steroids, Rescue Infliximab)"]},
            {"key": "gastro-3", "title": "Liver Cirrhosis & Complications (Ascites, SBP, Hepatic Encephalopathy)", "estimated_minutes": 50, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["Child-Pugh & MELD scoring models", "Spontaneous Bacterial Peritonitis (SBP) diagnostic paracentesis criteria (>250 PMNs/mm3)", "Lactulose and Rifaximin dosing in hepatic encephalopathy"]},
            {"key": "gastro-4", "title": "Acute Pancreatitis & Biliary Disease", "estimated_minutes": 40, "difficulty": "easy", "high_yield": False,
             "learning_objectives": ["Atlanta criteria for acute pancreatitis", "Glasgow/Ranson severity scoring and aggressive fluid resuscitation"]},
        ],
    },
    {
        "key": "nephrology", "title": "Nephrology & Renal Medicine", "icon": "Droplet",
        "description": "Acute kidney injury, chronic kidney disease, glomerulonephritis, and electrolyte balance.",
        "topics": [
            {"key": "neph-1", "title": "Acute Kidney Injury (Pre-renal, Intrinsic, Post-renal)", "estimated_minutes": 45, "difficulty": "moderate", "high_yield": True,
             "learning_objectives": ["KDIGO staging for AKI", "Urinary sodium & Fractional Excretion of Sodium (FENa) calculations", "Emergency indications for renal replacement therapy (AEIOU criteria)"]},
            {"key": "neph-2", "title": "Hyperkalemia Emergency Management", "estimated_minutes": 35, "difficulty": "easy", "high_yield": True,
             "learning_objectives": ["ECG signs of hyperkalemia (peaked T waves, QRS widening, sine wave)", "Membrane stabilization (Calcium Gluconate) vs shifting agents (Insulin/Dextrose)"]},
            {"key": "neph-3", "title": "Nephrotic vs Nephritic Syndromes", "estimated_minutes": 50, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["Triad of nephrotic syndrome (heavy proteinuria >3.5g, hypoalbuminemia, edema)", "Biopsy features of Minimal Change, FSGS, Membranous, and IgA Nephropathy"]},
            {"key": "neph-4", "title": "Chronic Kidney Disease & Bone-Mineral Disorders", "estimated_minutes": 40, "difficulty": "moderate", "high_yield": False,
             "learning_objectives": ["eGFR staging (G1-G5) and albuminuria categories (A1-A3)", "Management of anemia of CKD and renal osteodystrophy"]},
        ],
    },
    {
        "key": "neurology", "title": "Neurology & Stroke Medicine", "icon": "Brain",
        "description": "Cerebrovascular events, neuromuscular disorders, epilepsy, headache, and neurodegeneration.",
        "topics": [
            {"key": "neuro-1", "title": "Acute Ischemic & Hemorrhagic Stroke", "estimated_minutes": 55, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["Thrombolysis window (<4.5 hours) and Mechanical Thrombectomy (<24 hours)", "Oxfordshire Community Stroke Project (OCSP) stroke classification (TACS, PACS, LACS, POCS)", "Immediate secondary stroke prevention guidelines"]},
            {"key": "neuro-2", "title": "Status Epilepticus & Seizure Management", "estimated_minutes": 45, "difficulty": "moderate", "high_yield": True,
             "learning_objectives": ["Stepwise status epilepticus protocol (IV Lorazepam -> Levetiracetam/Phenytoin -> Anesthetic agents)", "Differentiate generalized vs focal seizure anti-epileptic drugs"]},
            {"key": "neuro-3", "title": "Multiple Sclerosis & Demyelinating Disorders", "estimated_minutes": 45, "difficulty": "moderate", "high_yield": False,
             "learning_objectives": ["McDonald criteria for MS diagnosis", "CSF oligoclonal bands and MRI plaque dissemination in time and space"]},
            {"key": "neuro-4", "title": "Parkinson's Disease & Movement Disorders", "estimated_minutes": 40, "difficulty": "easy", "high_yield": False,
             "learning_objectives": ["Cardinal motor symptoms (Bradykinesia, Resting tremor, Rigidity, Postural instability)", "Levodopa/Carbidopa side effects and motor fluctuations"]},
        ],
    },
    {
        "key": "infectious", "title": "Infectious Diseases & Antimicrobials", "icon": "ShieldAlert",
        "description": "Sepsis, HIV, Tuberculosis, tropical infections, and antimicrobial stewardship.",
        "topics": [
            {"key": "inf-1", "title": "Sepsis & Septic Shock (Sepsis-6 Bundle)", "estimated_minutes": 45, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["qSOFA score & SOFA score criteria", "Deliver Sepsis-6 within 1 hour (Blood cultures, Lactate, Urine output, O2, Abx, IV Fluids)", "Vasopressor targets in septic shock (MAP >= 65 mmHg with Norepinephrine)"]},
            {"key": "inf-2", "title": "Tuberculosis (Pulmonary & Extra-pulmonary)", "estimated_minutes": 45, "difficulty": "moderate", "high_yield": True,
             "learning_objectives": ["Standard RIPE regimen (Rifampicin, Isoniazid, Pyrazinamide, Ethambutol)", "Key medication toxicities (Rifampicin orange secretions, Ethambutol optic neuritis)"]},
            {"key": "inf-3", "title": "HIV Infection & Opportunistic Complications", "estimated_minutes": 50, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["CD4 count thresholds for opportunistic infections (PCP <200, Toxoplasmosis <100, MAC <50)", "Prophylaxis and treatment guidelines for PCP (Co-trimoxazole)"]},
        ],
    },
    {
        "key": "rheumatology", "title": "Rheumatology & Autoimmune Medicine", "icon": "Bone",
        "description": "Inflammatory arthritis, connective tissue diseases, vasculitis, and crystal arthropathies.",
        "topics": [
            {"key": "rheum-1", "title": "Rheumatoid Arthritis vs Osteoarthritis", "estimated_minutes": 40, "difficulty": "easy", "high_yield": True,
             "learning_objectives": ["Compare joint distribution (MCP/PIP vs DIP/First CMC)", "First-line DMARD therapy (Methotrexate, Folic Acid, biologics)"]},
            {"key": "rheum-2", "title": "Systemic Lupus Erythematosus (SLE) & Lupus Nephritis", "estimated_minutes": 45, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["ANA sensitivity vs Anti-dsDNA / Anti-Smith specificity", "Lupus nephritis screening, renal biopsy classification, and immunosuppression"]},
            {"key": "rheum-3", "title": "Giant Cell Arteritis & Polymyalgia Rheumatica", "estimated_minutes": 35, "difficulty": "moderate", "high_yield": True,
             "learning_objectives": ["Recognize GCA visual loss risk and STAT high-dose oral/IV steroids prior to biopsy", "Temporal artery biopsy findings (granulomatous inflammation)"]},
        ],
    },
    {
        "key": "hematology", "title": "Hematology & Oncology", "icon": "Droplets",
        "description": "Anemias, coagulation disorders, hematological malignancies, and transfusion medicine.",
        "topics": [
            {"key": "hem-1", "title": "Microcytic, Macrocytic & Normocytic Anemias", "estimated_minutes": 40, "difficulty": "easy", "high_yield": True,
             "learning_objectives": ["Interpret Ferritin, TIBC, Iron saturation in Iron Deficiency vs Chronic Disease", "B12 vs Folate deficiency neurological complications (Subacute Combined Degeneration)"]},
            {"key": "hem-2", "title": "Acute & Chronic Leukemias (AML, ALL, CML, CLL)", "estimated_minutes": 50, "difficulty": "difficult", "high_yield": False,
             "learning_objectives": ["Auer rods in AML vs Philadelphia chromosome t(9;22) BCR-ABL in CML", "Targeted tyrosine kinase inhibitors (Imatinib) and Tumor Lysis Syndrome prevention"]},
            {"key": "hem-3", "title": "Coagulation Disorders (DIC, TTP, ITP, Hemophilia)", "estimated_minutes": 45, "difficulty": "difficult", "high_yield": True,
             "learning_objectives": ["Pentad of TTP (Fever, Anemia, Thrombocytopenia, Renal failure, Neuro deficits)", "ADAMTS13 deficiency and immediate plasma exchange"]},
        ],
    },
]
