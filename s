import { initializeApp } from "https://www.gstatic.com/firebasejs/10.8.1/firebase-app.js";
import { getAuth, createUserWithEmailAndPassword, signInWithEmailAndPassword, signOut, signInWithPopup, GoogleAuthProvider, onAuthStateChanged } from "https://www.gstatic.com/firebasejs/10.8.1/firebase-auth.js";
import { getDatabase, ref, set, onValue } from "https://www.gstatic.com/firebasejs/10.8.1/firebase-database.js";

const firebaseConfig = {
    apiKey: "AIzaSyAwrpo_McpHunMm2bcIg4J6nJBnaOY95xE",
    authDomain: "tracker-360r.firebaseapp.com",
    databaseURL: "https://tracker-360r-default-rtdb.asia-southeast1.firebasedatabase.app",
    projectId: "tracker-360r",
    storageBucket: "tracker-360r.firebasestorage.app",
    messagingSenderId: "685195495220",
    appId: "1:685195495220:web:78df407a6fe7915b8b8761",
    measurementId: "G-FPM2D6FNYE"
};

let app, auth, database, googleProvider;
let isCloudActive = false;

try {
    if (firebaseConfig.apiKey !== "YOUR_API_KEY") {
        app = initializeApp(firebaseConfig);
        auth = getAuth(app);
        database = getDatabase(app);
        googleProvider = new GoogleAuthProvider();
        isCloudActive = true;
    } else {
        console.warn("360R Tracking System: Operating in local fallback infrastructure mode.");
    }
} catch (error) {
    console.error("Firebase Configuration Initialization halted engine:", error);
}

document.addEventListener('DOMContentLoaded', () => {
    const state = {
        attendanceHistory: {}, 
        todaySelection: { lecture: false, question: false, revision: false },
        currentDateStr: "", 
        charts: { bar: null, pie: null },
        calendar: { month: 5, year: 2026 },
        currentUser: null,
        authMode: 'login' 
    };

    const motivationalQuotes = [
        "Consistency beats intensity. Every single day counts.",
        "One Present Day at a Time. Keep building the block.",
        "Future IITians Show Up Daily. No excuses, no shortcuts.",
        "Small daily wins create massive structural ranks.",
        "The price of discipline is always less than the pain of regret."
    ];

    const DOM = {
        currentDate: document.getElementById('current-date'),
        taskLectures: document.getElementById('task-lectures'),
        taskQuestions: document.getElementById('task-questions'),
        taskRevision: document.getElementById('task-revision'),
        statusCard: document.getElementById('status-card'),
        statusDisplay: document.getElementById('status-display'),
        statusSubtext: document.getElementById('status-subtext'),
        finalizeBtn: document.getElementById('finalize-btn'),
        motivationQuote: document.getElementById('motivation-quote'),
        currentStreak: document.getElementById('current-streak'),
        longestStreak: document.getElementById('longest-streak'),
        statPresentCount: document.getElementById('stat-present-count'),
        statAbsentCount: document.getElementById('stat-absent-count'),
        heatmapGrid: document.getElementById('heatmap-grid'),
        toastContainer: document.getElementById('toast-container'),
        barChartCanvas: document.getElementById('barChartMonthly'),
        pieChartCanvas: document.getElementById('pieChartRatio'),
        
        calendarModal: document.getElementById('calendar-modal'),
        calendarTrigger: document.getElementById('calendar-trigger'),
        closeCalendarModal: document.getElementById('close-calendar-modal'),
        calendarGrid: document.getElementById('calendar-grid-ui'),
        calendarDetails: document.getElementById('calendar-details'),
        calendarMonthLbl: document.getElementById('calendar-month'),
        prevMonthBtn: document.getElementById('prev-month'),
        nextMonthBtn: document.getElementById('next-month'),
        
        authModalTrigger: document.getElementById('auth-modal-trigger'),
        authTriggerText: document.getElementById('auth-trigger-text'),
        cloudIconIndicator: document.getElementById('cloud-icon-indicator'),
        authModal: document.getElementById('auth-modal'),
        closeAuthModal: document.getElementById('close-auth-modal'),
        authLoggedOut: document.getElementById('auth-logged-out'),
        authLoggedIn: document.getElementById('auth-logged-in'),
        userDisplayEmail: document.getElementById('user-display-email'),
        btnGoogle: document.getElementById('btn-google'),
        btnLogout: document.getElementById('btn-logout'),

        // Slider specific UI elements
        modalAuthTitle: document.getElementById('modal-auth-title'),
        loginSlide: document.getElementById('login-slide'),
        signupSlide: document.getElementById('signup-slide'),
        formInner: document.querySelector('.form-inner'),
        
        loginEmail: document.getElementById('login-email'),
        loginPassword: document.getElementById('login-password'),
        btnSubmitLogin: document.getElementById('btn-submit-login'),

        signupEmail: document.getElementById('signup-email'),
        signupPassword: document.getElementById('signup-password'),
        signupConfirm: document.getElementById('signup-confirm'),
        btnSubmitSignup: document.getElementById('btn-submit-signup')
    };

    function init() {
        setupDateEngine();
        loadLocalStorageData(); 
        bindInputEventListeners();
        setupInteractiveModalPanels();
        
        if (isCloudActive) {
            bindAuthEventListeners();
            setupFirebaseObserver();
        } else {
            DOM.authModalTrigger.onclick = () => {
                showToastMessage("Firebase parameters missing! Please update your keys.");
            };
        }

        evaluateTodayStatus();
        calculateMetricsAndStreaks();
        renderHeatmapGraph();
        renderAnalyticsCharts();
        displayDailyQuote();
        checkMidnightRollover();
        setupHeatmapTooltips();
    }

    function setupDateEngine() {
        const now = new Date();
        const options = { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' };
        DOM.currentDate.textContent = now.toLocaleDateString('en-US', options);
        state.currentDateStr = formatDateToISO(now);
        state.calendar.month = now.getMonth();
        state.calendar.year = now.getFullYear();
    }

    function loadLocalStorageData() {
        const savedHistory = localStorage.getItem('360R_attendanceHistory');
        if (savedHistory) { 
            try { 
                state.attendanceHistory = JSON.parse(savedHistory); 
                migrateOldSchemaData();
            } catch(e) { state.attendanceHistory = {}; } 
        }
        
        const savedTasks = localStorage.getItem('360R_todayTasks');
        const savedTasksDate = localStorage.getItem('360R_todayTasksDate');
        
        if (savedTasksDate === state.currentDateStr && savedTasks) {
            try {
                state.todaySelection = JSON.parse(savedTasks);
                DOM.taskLectures.checked = state.todaySelection.lecture;
                DOM.taskQuestions.checked = state.todaySelection.question;
                DOM.taskRevision.checked = state.todaySelection.revision;
            } catch(e) { state.todaySelection = { lecture: false, question: false, revision: false }; }
        } else {
            localStorage.setItem('360R_todayTasksDate', state.currentDateStr);
            saveWorkingTasksState();
        }
        if (state.attendanceHistory[state.currentDateStr]) { lockInputsOnFinalizedState(); }
    }

    function migrateOldSchemaData() {
        let changed = false;
        Object.keys(state.attendanceHistory).forEach(key => {
            if (typeof state.attendanceHistory[key] === 'string') {
                const statusVal = state.attendanceHistory[key];
                state.attendanceHistory[key] = {
                    status: statusVal,
                    lecture: statusVal === 'Present',
                    question: statusVal === 'Present',
                    revision: statusVal === 'Present',
                    note: ""
                };
                changed = true;
            }
        });
        if (changed) localStorage.setItem('360R_attendanceHistory', JSON.stringify(state.attendanceHistory));
    }

    function saveWorkingTasksState() { 
        localStorage.setItem('360R_todayTasks', JSON.stringify(state.todaySelection)); 
    }

    function syncDataToCloudEngine() {
        if (!isCloudActive || !state.currentUser) return;
        const targetRef = ref(database, 'users/' + state.currentUser.uid + '/attendanceHistory');
        set(targetRef, state.attendanceHistory).catch(err => console.error("Cloud error:", err));
    }

    function setupFirebaseObserver() {
        onAuthStateChanged(auth, (user) => {
            if (user) {
                state.currentUser = user;
                DOM.userDisplayEmail.textContent = user.email || "Sync Account Attached";
                DOM.authTriggerText.textContent = "Synced";
                DOM.authModalTrigger.classList.add('cloud-active');
                DOM.cloudIconIndicator.className = "fa-solid fa-cloud-check text-success";
                
                DOM.authLoggedOut.classList.add('hidden');
                DOM.authLoggedIn.classList.remove('hidden');
                
                const userRecordRef = ref(database, 'users/' + user.uid + '/attendanceHistory');
                onValue(userRecordRef, (snapshot) => {
                    const cloudData = snapshot.val();
                    if (cloudData) {
                        state.attendanceHistory = cloudData;
                        localStorage.setItem('360R_attendanceHistory', JSON.stringify(state.attendanceHistory));
                        if (state.attendanceHistory[state.currentDateStr]) { lockInputsOnFinalizedState(); } else { unlockInputsFromFinalizedState(); loadLocalStorageData(); }
                        refreshUIVisuals();
                    } else {
                        if (Object.keys(state.attendanceHistory).length > 0) syncDataToCloudEngine();
                    }
                });
            } else {
                state.currentUser = null;
                DOM.authTriggerText.textContent = "Cloud Sync";
                DOM.authModalTrigger.classList.remove('cloud-active');
                DOM.cloudIconIndicator.className = "fa-solid fa-cloud animate-pulse";
                DOM.authLoggedOut.classList.remove('hidden');
                DOM.authLoggedIn.classList.add('hidden');
            }
        });
    }

    function bindAuthEventListeners() {
        DOM.btnSubmitLogin.onclick = (e) => {
            e.preventDefault();
            const email = DOM.loginEmail.value.trim();
            const password = DOM.loginPassword.value;
            if (!email || !password) return showToastMessage("Please enter email parameters and password credentials.");
            
            signInWithEmailAndPassword(auth, email, password)
                .then(() => { showToastMessage("Authentication established. Cloud synchronizer active."); DOM.authModal.style.display = 'none'; })
                .catch(err => showToastMessage(`Login Error: ${err.message}`));
        };

        DOM.btnSubmitSignup.onclick = (e) => {
            e.preventDefault();
            const email = DOM.signupEmail.value.trim();
            const password = DOM.signupPassword.value;
            const confirm = DOM.signupConfirm.value;
            
            if (!email || !password) return showToastMessage("Please enter email parameters and password credentials.");
            if (password !== confirm) return showToastMessage("Password confirmation mismatch. Try again.");
            
            createUserWithEmailAndPassword(auth, email, password)
                .then(() => { showToastMessage("Cloud ledger container initialized successfully!"); DOM.authModal.style.display = 'none'; })
                .catch(err => showToastMessage(`Registration Error: ${err.message}`));
        };

        DOM.btnGoogle.onclick = () => {
            signInWithPopup(auth, googleProvider)
                .then(() => { showToastMessage("Google profile sequence linked safely."); DOM.authModal.style.display = 'none'; })
                .catch(err => showToastMessage(`Google Auth Exception: ${err.message}`));
        };

        DOM.btnLogout.onclick = () => {
            signOut(auth).then(() => {
                showToastMessage("Disconnected from global storage nodes. Local tracking context retained.");
                DOM.authModal.style.display = 'none';
                state.attendanceHistory = {};
                localStorage.removeItem('360R_attendanceHistory');
                unlockInputsFromFinalizedState();
                refreshUIVisuals();
            });
        };
    }

    function bindInputEventListeners() {
        const handleCheckboxChange = () => {
            state.todaySelection.lecture = DOM.taskLectures.checked;
            state.todaySelection.question = DOM.taskQuestions.checked;
            state.todaySelection.revision = DOM.taskRevision.checked;
            saveWorkingTasksState();
            evaluateTodayStatus();
        };
        DOM.taskLectures.addEventListener('change', handleCheckboxChange);
        DOM.taskQuestions.addEventListener('change', handleCheckboxChange);
        DOM.taskRevision.addEventListener('change', handleCheckboxChange);
        DOM.finalizeBtn.addEventListener('click', finalizeTransactionEvent);
    }

    function evaluateTodayStatus() {
        const isPresent = state.todaySelection.lecture && state.todaySelection.question && state.todaySelection.revision;
        if (isPresent) {
            DOM.statusCard.className = "card glass status-present";
            DOM.statusDisplay.textContent = "Present Today";
            DOM.statusSubtext.textContent = "Optimal target loop achieved! Finalize to seal metric trajectory.";
        } else {
            DOM.statusCard.className = "card glass status-absent";
            DOM.statusDisplay.textContent = "Absent Today";
            DOM.statusSubtext.textContent = "Complete remaining core targets to flip status to Present.";
        }
        
        if (state.attendanceHistory[state.currentDateStr]) {
            const absoluteStatus = state.attendanceHistory[state.currentDateStr].status;
            DOM.statusCard.className = `card glass status-${absoluteStatus.toLowerCase()}`;
            DOM.statusDisplay.textContent = `${absoluteStatus} (Finalized)`;
            DOM.statusSubtext.textContent = "This track sequence is securely committed to your ledger history.";
        }
    }

    function finalizeTransactionEvent() {
        if (state.attendanceHistory[state.currentDateStr]) return;
        const calculatedStatus = (state.todaySelection.lecture && state.todaySelection.question && state.todaySelection.revision) ? "Present" : "Absent";
        
        state.attendanceHistory[state.currentDateStr] = {
            status: calculatedStatus,
            lecture: state.todaySelection.lecture,
            question: state.todaySelection.question,
            revision: state.todaySelection.revision,
            note: ""
        };
        
        localStorage.setItem('360R_attendanceHistory', JSON.stringify(state.attendanceHistory));
        syncDataToCloudEngine();
        
        lockInputsOnFinalizedState();
        refreshUIVisuals();
        
        if (calculatedStatus === "Present") {
            confetti({ particleCount: 120, spread: 70, origin: { y: 0.6 }, colors: ['#3b82f6', '#22c55e', '#ffffff'] });
            showToastMessage("Target Locked: Excellent execution trajectory!");
        } else { 
            showToastMessage("Record Filed: Absent day logged."); 
        }
    }

    function lockInputsOnFinalizedState() {
        DOM.taskLectures.disabled = true; DOM.taskQuestions.disabled = true; DOM.taskRevision.disabled = true;
        DOM.taskLectures.parentElement.classList.add('tasks-disabled');
        DOM.taskQuestions.parentElement.classList.add('tasks-disabled');
        DOM.taskRevision.parentElement.classList.add('tasks-disabled');
        DOM.finalizeBtn.disabled = true;
        DOM.finalizeBtn.innerHTML = '<span>Day Sequence Finalized</span> <i class="fa-solid fa-check-double"></i>';
    }

    function unlockInputsFromFinalizedState() {
        DOM.taskLectures.disabled = false; DOM.taskQuestions.disabled = false; DOM.taskRevision.disabled = false;
        DOM.taskLectures.checked = false; DOM.taskQuestions.checked = false; DOM.taskRevision.checked = false;
        state.todaySelection = { lecture: false, question: false, revision: false };
        saveWorkingTasksState();
        DOM.taskLectures.parentElement.classList.remove('tasks-disabled');
        DOM.taskQuestions.parentElement.classList.remove('tasks-disabled');
        DOM.taskRevision.parentElement.classList.remove('tasks-disabled');
        DOM.finalizeBtn.disabled = false;
        DOM.finalizeBtn.innerHTML = '<span>Finalize Today</span> <i class="fa-solid fa-bolt"></i>';
    }

    function refreshUIVisuals() {
        evaluateTodayStatus();
        calculateMetricsAndStreaks();
        renderHeatmapGraph();
        renderAnalyticsCharts();
    }

    function calculateMetricsAndStreaks() {
        const records = Object.keys(state.attendanceHistory).sort();
        let presentCount = 0, absentCount = 0;
        records.forEach(dateKey => { 
            if (state.attendanceHistory[dateKey].status === "Present") presentCount++; else if (state.attendanceHistory[dateKey].status === "Absent") absentCount++; 
        });
        DOM.statPresentCount.textContent = presentCount; DOM.statAbsentCount.textContent = absentCount;

        let maxStreak = 0, tempStreak = 0;
        const chronologicalKeys = [...records].sort((a,b) => new Date(a) - new Date(b));
        chronologicalKeys.forEach(key => {
            if (state.attendanceHistory[key].status === "Present") { 
                tempStreak++; 
                if (tempStreak > maxStreak) maxStreak = tempStreak; 
            } else if (state.attendanceHistory[key].status === "Absent") { tempStreak = 0; }
        });

        let currentStreak = 0;
        let evaluationTargetStr = state.currentDateStr;
        let matchingStreakLinkFound = true;
        if (!state.attendanceHistory[evaluationTargetStr]) {
            const yesterdayDateObj = new Date(); yesterdayDateObj.setDate(yesterdayDateObj.getDate() - 1);
            evaluationTargetStr = formatDateToISO(yesterdayDateObj);
        }
        while (matchingStreakLinkFound) {
            if (state.attendanceHistory[evaluationTargetStr] && state.attendanceHistory[evaluationTargetStr].status === "Present") {
                currentStreak++;
                const prev = new Date(evaluationTargetStr); prev.setDate(prev.getDate() - 1);
                evaluationTargetStr = formatDateToISO(prev);
            } else { matchingStreakLinkFound = false; }
        }
        DOM.currentStreak.textContent = `${currentStreak} Day${currentStreak === 1 ? '' : 's'}`;
        DOM.longestStreak.textContent = `${maxStreak} Day${maxStreak === 1 ? '' : 's'}`;
    }

    function renderHeatmapGraph() {
        DOM.heatmapGrid.innerHTML = "";
        const startDate = new Date(2026, 5, 8); 
        const endDate = new Date(2027, 0, 1);   
        let iterDate = new Date(startDate);
        while (iterDate <= endDate) {
            const dateStrKey = formatDateToISO(iterDate);
            const squareNode = document.createElement('div');
            squareNode.classList.add('heatmap-day');
            
            const rec = state.attendanceHistory[dateStrKey];
            if (rec && rec.status === "Present") squareNode.classList.add('bg-present');
            else if (rec && rec.status === "Absent") squareNode.classList.add('bg-absent');
            else squareNode.classList.add('bg-empty');
            
            const date
