import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchHouseholds from '@salesforce/apex/Family360Controller.searchHouseholds';
import getHousehold from '@salesforce/apex/Family360Controller.getHousehold';
import getInsights from '@salesforce/apex/Family360Controller.getInsights';
import createTask from '@salesforce/apex/Family360Controller.createTask';
import addNote from '@salesforce/apex/Family360Controller.addNote';
import getDeskQuestions from '@salesforce/apex/Family360Controller.getDeskQuestions';
import askDesk from '@salesforce/apex/Family360Controller.askDesk';
import markDeskOutcome from '@salesforce/apex/Family360Controller.markDeskOutcome';
import getEnquiryOptions from '@salesforce/apex/Family360Controller.getEnquiryOptions';
import saveEnquiry from '@salesforce/apex/Family360Controller.saveEnquiry';
import applyEnquiry from '@salesforce/apex/Family360Controller.applyEnquiry';
import discardEnquiry from '@salesforce/apex/Family360Controller.discardEnquiry';
import saveProfile from '@salesforce/apex/Family360Controller.saveProfile';
import getVisitSummary from '@salesforce/apex/Family360Controller.getVisitSummary';

const emptyEnquiry = () => ({
    enquiryType: '',
    channel: 'Phone',
    preferredDate: null,
    backupDate: null,
    preferredTime: '',
    kids: null,
    adults: null,
    pizzas: null,
    players: null,
    laserPackage: '',
    packageInterest: '',
    roomPreference: '',
    addOns: [],
    changes: [],
    cancelReason: '',
    depositDiscussed: false,
    allergyFlagged: false,
    notes: '',
    followUpDate: null,
    bookingId: ''
});
const NUMBER_FIELDS = ['kids', 'adults', 'pizzas', 'players'];

const SEARCH_DELAY_MS = 350;
const STATUS_CLASS = {
    Answered: 'badge badge-good',
    'Not in records': 'badge badge-quiet',
    Blocked: 'badge badge-bad',
    Resolved: 'badge badge-good',
    Escalated: 'badge badge-warn'
};

export default class Family360 extends NavigationMixin(LightningElement) {
    @api recordId;

    searchTerm = '';
    @track hits = [];
    searching = false;
    searchedOnce = false;

    @track household;
    loadingHousehold = false;

    @track insights;
    loadingInsights = false;

    @track deskQuestions = [];
    selectedKeys = [];
    customQuestion = '';
    focusRecordId = '';
    @track enquiry = emptyEnquiry();
    @track enquiryOptions = {
        intents: [], channels: [], addOns: [], changes: [], packages: [], rooms: [], times: [],
        cancelReasons: [], laserPackages: [], visitFrequency: [], heardAbout: [], interests: [], contactPrefs: []
    };
    savingEnquiry = false;
    @track draft;
    applying = false;
    @track visit;
    loadingVisit = false;
    @track profileDraft = {};
    editingProfile = false;
    savingProfile = false;
    @track deskAnswers = [];
    asking = false;
    deskError;

    noteText = '';
    noteTeamMember = '';
    savingNote = false;

    searchTimer;

    @wire(getDeskQuestions)
    wiredQuestions({ data }) {
        if (data) {
            this.deskQuestions = data;
        }
    }

    @wire(getEnquiryOptions)
    wiredEnquiryOptions({ data }) {
        if (data) {
            this.enquiryOptions = data;
        }
    }

    connectedCallback() {
        if (this.recordId) {
            this.loadHousehold(this.recordId);
        }
    }

    get showBack() {
        return !this.recordId;
    }

    get hasHits() {
        return this.hits.length > 0;
    }

    get showNoResults() {
        return this.searchedOnce && !this.searching && !this.hasHits && this.searchTerm.length >= 3;
    }

    get initials() {
        const n = (this.household && this.household.name) || '';
        return n.split(/\s+/).filter((w) => /[A-Za-z]/.test(w)).slice(0, 2).map((w) => w[0].toUpperCase()).join('') || '#';
    }

    get heroSub() {
        const h = this.household;
        return [h.phone, h.customerSince ? `Customer since ${h.customerSince}` : null].filter(Boolean).join(' · ');
    }

    get stats() {
        const h = this.household;
        if (!h) {
            return [];
        }
        const money = new Intl.NumberFormat('en-CA', { style: 'currency', currency: 'CAD', maximumFractionDigits: 0 });
        return [
            { key: 'bookings', value: h.bookingCount || 0, label: 'Bookings' },
            { key: 'parties', value: h.partiesHosted || 0, label: 'Parties hosted' },
            { key: 'lastVisit', value: (this.visit && this.visit.lastVisit) || (this.loadingVisit ? '…' : '—'), label: 'Last visit' },
            { key: 'visits', value: this.visit ? this.visit.visitsThisYear : '…', label: 'Visits this year' },
            { key: 'spend', value: this.visit ? money.format(this.visit.spend12Months || 0) : '…', label: 'Spend, last 12 months' },
            { key: 'unpaid', value: h.unpaidOrders || 0, label: 'Unpaid orders', alert: (h.unpaidOrders || 0) > 0 },
            { key: 'next', value: h.nextEvent || '—', label: 'Next booking' }
        ].map((s) => ({ ...s, cls: s.alert ? 'stat stat-alert' : 'stat' }));
    }

    get people() {
        return this.household ? this.household.people : [];
    }

    get hasPeople() {
        return this.people.length > 0;
    }

    get historyTabs() {
        const h = this.household;
        if (!h) {
            return [];
        }
        return [
            { key: 'bookings', label: `Parties (${h.bookings.length})`, rows: h.bookings, empty: 'No bookings yet.' },
            { key: 'orders', label: `Orders (${h.orders.length})`, rows: h.orders, empty: 'No Square orders.' },
            { key: 'notes', label: `Notes (${h.notes.length})`, rows: h.notes, empty: 'No staff notes yet.' },
            { key: 'enquiries', label: `Enquiries (${h.enquiries.length})`, rows: h.enquiries, empty: 'No enquiries logged.' },
            { key: 'camps', label: `Camps (${h.camps.length})`, rows: h.camps, empty: 'No camp registrations.' }
        ].map((t) => ({ ...t, hasRows: t.rows.length > 0 }));
    }

    get quickPicks() {
        return this.deskQuestions.map((q) => ({
            ...q,
            cls: this.selectedKeys.includes(q.key) ? 'pick pick-on' : 'pick',
            pressed: this.selectedKeys.includes(q.key) ? 'true' : 'false'
        }));
    }

    get aboutOptions() {
        const opts = (this.household && this.household.recordOptions) || [];
        return [{ label: 'The whole family', value: '' }, ...opts];
    }

    get questionCount() {
        return this.selectedKeys.length + (this.customQuestion.trim() ? 1 : 0);
    }

    get askLabel() {
        const n = this.questionCount;
        return n <= 1 ? 'Ask' : `Ask ${n} questions`;
    }

    get askDisabled() {
        return this.asking || this.questionCount === 0;
    }

    get charsLeft() {
        return `${300 - this.customQuestion.length} characters left`;
    }

    get visitSource() {
        if (!this.visit) {
            return '';
        }
        return this.visit.note ? `${this.visit.source}. ${this.visit.note}` : this.visit.source;
    }

    get segments() {
        return (this.household && this.household.profile && this.household.profile.segments) || [];
    }

    get bookingPickOptions() {
        const opts = (this.household && this.household.bookingOptions) || [];
        return opts.length ? opts : [{ label: 'No bookings on file', value: '' }];
    }

    withBlank(list, label) {
        return [{ label: label || '— Not sure yet —', value: '' }, ...(list || [])];
    }

    get packageOptions() {
        return this.withBlank(this.enquiryOptions.packages);
    }

    get roomOptions() {
        return this.withBlank(this.enquiryOptions.rooms);
    }

    get timeOptions() {
        return this.withBlank(this.enquiryOptions.times, '— Any time —');
    }

    get laserOptions() {
        return this.withBlank(this.enquiryOptions.laserPackages);
    }

    get cancelOptions() {
        return this.withBlank(this.enquiryOptions.cancelReasons, '— Choose a reason —');
    }

    get intent() {
        return this.enquiry.enquiryType;
    }

    get isNewParty() {
        return this.intent === 'New party';
    }

    get isChange() {
        return this.intent === 'Change a booking';
    }

    get isLaser() {
        return this.intent === 'Laser tag';
    }

    get isDropIn() {
        return this.intent === 'Drop-in';
    }

    get isCamp() {
        return this.intent === 'Camp or class';
    }

    get hasIntent() {
        return !!this.intent;
    }

    get changeSet() {
        return new Set(this.enquiry.changes || []);
    }

    get changeDate() {
        return this.isChange && this.changeSet.has('Date');
    }

    get changeHeadcount() {
        return this.isChange && this.changeSet.has('Headcount');
    }

    get changeRoom() {
        return this.isChange && this.changeSet.has('Room');
    }

    get changePackage() {
        return this.isChange && this.changeSet.has('Package');
    }

    get changeAddOns() {
        return this.isChange && this.changeSet.has('Add-ons');
    }

    get changeCancel() {
        return this.isChange && this.changeSet.has('Cancel');
    }

    get showHeadcount() {
        return this.isNewParty || this.isDropIn || this.changeHeadcount;
    }

    get showRoomPackage() {
        return this.isNewParty;
    }

    get showAddOns() {
        return this.isNewParty || this.changeAddOns;
    }

    get dateLabel() {
        if (this.isChange) {
            return 'New date';
        }
        return this.isNewParty ? 'Preferred date' : 'Date';
    }

    get showDate() {
        return this.isNewParty || this.isLaser || this.isDropIn || this.changeDate;
    }

    get dateRequired() {
        return this.isNewParty;
    }

    get todayIso() {
        const d = new Date();
        return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
    }

    get saveEnquiryLabel() {
        return this.isChange || this.isNewParty || this.isLaser || this.isDropIn ? 'Save and preview' : 'Save note';
    }

    get saveEnquiryDisabled() {
        return this.savingEnquiry || !this.intent;
    }

    get draftHasAction() {
        return this.draft && this.draft.actionLabel && this.draft.status === 'Draft';
    }

    get draftApplyDisabled() {
        return this.applying || !this.draft || !this.draft.canApply;
    }

    get draftStatusClass() {
        const st = this.draft && this.draft.status;
        if (st === 'Applied') {
            return 'badge badge-good';
        }
        if (st === 'Held in sandbox' || st === 'Discarded') {
            return 'badge badge-warn';
        }
        return 'badge badge-ai';
    }

    get draftIsOpen() {
        return this.draft && this.draft.status === 'Draft';
    }

    get profile() {
        return (this.household && this.household.profile) || {};
    }

    get profileQuestions() {
        const p = this.profile;
        const o = this.enquiryOptions;
        const all = [
            { key: 'visitFrequency', label: 'How often do you visit us?', value: p.visitFrequency, options: o.visitFrequency, kind: 'buttons' },
            { key: 'interests', label: 'What is your family interested in?', value: (p.interests || []).join(', '), options: o.interests, kind: 'multi' },
            { key: 'heardAbout', label: 'How did you first hear about us?', value: p.heardAbout, options: o.heardAbout, kind: 'combo' },
            { key: 'preferredContact', label: 'Best way to reach you?', value: p.preferredContact, options: o.contactPrefs, kind: 'buttons' },
            { key: 'schoolDaycare', label: 'School or daycare (optional)', value: p.schoolDaycare, kind: 'text' }
        ];
        return all.map((q) => ({
            ...q,
            answered: !!q.value,
            show: this.editingProfile || !q.value,
            isButtons: q.kind === 'buttons',
            isMulti: q.kind === 'multi',
            isCombo: q.kind === 'combo',
            isText: q.kind === 'text',
            draftValue: this.profileDraft[q.key] !== undefined ? this.profileDraft[q.key] : q.kind === 'multi' ? p.interests || [] : q.value || ''
        }));
    }

    get openProfileQuestions() {
        return this.profileQuestions.filter((q) => q.show);
    }

    get answeredProfile() {
        return this.profileQuestions.filter((q) => q.answered && !this.editingProfile);
    }

    get hasOpenProfileQuestions() {
        return this.openProfileQuestions.length > 0;
    }

    get profileStatus() {
        const n = this.profile.unanswered || 0;
        if (this.editingProfile) {
            return 'Editing';
        }
        return n === 0 ? `Confirmed ${this.profile.updatedOn || ''}`.trim() : `${n} to ask`;
    }

    get profileEditLabel() {
        return this.editingProfile ? 'Cancel' : 'Edit';
    }

    get answerCards() {
        return this.deskAnswers.map((a) => ({
            ...a,
            badgeClass: STATUS_CLASS[a.outcome || a.status] || 'badge badge-quiet',
            badgeText: a.outcome || a.status,
            hasLinks: a.sourceLinks && a.sourceLinks.length > 0,
            canMark: !a.outcome && a.status !== 'Blocked'
        }));
    }

    get hasAnswers() {
        return this.deskAnswers.length > 0;
    }

    get deskHistory() {
        const rows = (this.household && this.household.deskHistory) || [];
        return rows.map((r) => ({ ...r, badgeClass: STATUS_CLASS[r.badge] || 'badge badge-quiet' }));
    }

    get hasDeskHistory() {
        return this.deskHistory.length > 0;
    }

    get teamMemberOptions() {
        const values = (this.household && this.household.teamMembers) || [];
        return [{ label: '— Team member —', value: '' }, ...values.map((v) => ({ label: v, value: v }))];
    }

    get hasOpenTasks() {
        return this.household && this.household.openTasks.length > 0;
    }

    get insightTasks() {
        if (!this.insights || !this.insights.suggestedTasks) {
            return [];
        }
        return this.insights.suggestedTasks.map((t, i) => ({
            ...t,
            key: `t${i}`,
            dueLabel: t.dueInDays === 0 ? 'Due today' : `Due in ${t.dueInDays} day${t.dueInDays === 1 ? '' : 's'}`
        }));
    }

    get insightList() {
        return this.insights && this.insights.insights ? this.insights.insights.map((x, i) => ({ ...x, key: `i${i}` })) : [];
    }

    get hasInsightTasks() {
        return this.insightTasks.length > 0;
    }

    get hasInsightList() {
        return this.insightList.length > 0;
    }

    get insightsButtonLabel() {
        return this.insights ? 'Refresh' : 'Get insights';
    }

    get noteDisabled() {
        return this.savingNote || !this.noteText.trim();
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value || '';
        window.clearTimeout(this.searchTimer);
        if (this.searchTerm.trim().length < 3) {
            this.hits = [];
            this.searchedOnce = false;
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimer = window.setTimeout(() => this.runSearch(), SEARCH_DELAY_MS);
    }

    async runSearch() {
        this.searching = true;
        try {
            this.hits = await searchHouseholds({ term: this.searchTerm.trim() });
            this.searchedOnce = true;
        } catch (e) {
            this.toast('Search failed', this.errorText(e), 'error');
        } finally {
            this.searching = false;
        }
    }

    handleSelectHit(event) {
        const id = event.currentTarget.dataset.id;
        this.hits = [];
        this.searchedOnce = false;
        this.loadHousehold(id);
    }

    handleBack() {
        this.household = undefined;
        this.insights = undefined;
        this.visit = undefined;
        this.draft = undefined;
        this.deskAnswers = [];
        this.selectedKeys = [];
    }

    async loadHousehold(accountId) {
        this.loadingHousehold = true;
        this.insights = undefined;
        this.deskAnswers = [];
        this.selectedKeys = [];
        this.customQuestion = '';
        this.focusRecordId = '';
        this.enquiry = emptyEnquiry();
        this.draft = undefined;
        this.editingProfile = false;
        this.profileDraft = {};
        this.loadVisit(accountId);
        try {
            this.household = await getHousehold({ accountId });
        } catch (e) {
            this.toast('Could not load household', this.errorText(e), 'error');
        } finally {
            this.loadingHousehold = false;
        }
    }

    async reloadHousehold() {
        try {
            this.household = await getHousehold({ accountId: this.household.accountId });
        } catch (e) {
            this.toast('Could not refresh', this.errorText(e), 'error');
        }
    }

    handleTogglePick(event) {
        const key = event.currentTarget.dataset.key;
        this.selectedKeys = this.selectedKeys.includes(key)
            ? this.selectedKeys.filter((k) => k !== key)
            : [...this.selectedKeys, key];
    }

    handleClearQuestions() {
        this.selectedKeys = [];
        this.customQuestion = '';
    }

    handleCustomQuestion(event) {
        this.customQuestion = (event.target.value || '').slice(0, 300);
    }

    handleFocusRecord(event) {
        this.focusRecordId = event.detail.value;
    }

    handleEnquiryField(event) {
        const field = event.target.dataset.field;
        let value;
        if (event.target.type === 'toggle' || event.target.type === 'checkbox') {
            value = event.target.checked;
        } else if (event.detail && event.detail.value !== undefined) {
            value = event.detail.value;
        } else {
            value = event.target.value;
        }
        if (NUMBER_FIELDS.includes(field)) {
            value = value === '' || value === null || value === undefined ? null : parseInt(value, 10);
        }
        this.enquiry = { ...this.enquiry, [field]: value };
        if (field === 'enquiryType') {
            this.draft = undefined;
            const keep = { enquiryType: value, channel: this.enquiry.channel, notes: this.enquiry.notes };
            this.enquiry = { ...emptyEnquiry(), ...keep };
            if (value === 'Change a booking' && this.household && this.household.bookingOptions.length) {
                this.enquiry = { ...this.enquiry, bookingId: this.household.bookingOptions[0].value };
            }
        }
    }

    handleResetEnquiry() {
        this.enquiry = emptyEnquiry();
        this.draft = undefined;
    }

    async handleSaveEnquiry() {
        const inputs = [...this.template.querySelectorAll('.enquiry-form lightning-input, .enquiry-form lightning-combobox, .enquiry-form lightning-textarea')];
        const invalid = inputs.filter((el) => typeof el.reportValidity === 'function' && !el.reportValidity());
        if (invalid.length) {
            this.toast('Check the form', `Please fix: ${invalid.map((el) => el.label).join(', ')}`, 'warning');
            return;
        }
        this.savingEnquiry = true;
        try {
            const e = this.enquiry;
            this.draft = await saveEnquiry({
                accountId: this.household.accountId,
                inputJson: JSON.stringify({
                    ...e,
                    addOns: [...(e.addOns || [])],
                    changes: [...(e.changes || [])],
                    preferredTime: e.preferredTime || null,
                    laserPackage: e.laserPackage || null,
                    packageInterest: e.packageInterest || null,
                    roomPreference: e.roomPreference || null,
                    cancelReason: e.cancelReason || null,
                    bookingId: this.isChange ? e.bookingId || null : null,
                    teamMember: this.noteTeamMember || null
                })
            });
            this.toast('Saved', this.draft.actionLabel ? 'Review the draft below, then confirm.' : 'Saved as a staff note.', 'success');
            this.enquiry = emptyEnquiry();
            await this.reloadHousehold();
        } catch (err) {
            this.toast('Could not save', this.errorText(err), 'error');
        } finally {
            this.savingEnquiry = false;
        }
    }

    async handleApplyDraft() {
        this.applying = true;
        try {
            this.draft = await applyEnquiry({ enquiryId: this.draft.enquiryId });
            this.toast(this.draft.status === 'Applied' ? 'Done' : this.draft.status, this.draft.status === 'Applied' ? `${this.draft.target} updated.` : this.draft.blockedReason, this.draft.status === 'Applied' ? 'success' : 'warning');
            await this.reloadHousehold();
        } catch (err) {
            this.toast('Could not apply', this.errorText(err), 'error');
        } finally {
            this.applying = false;
        }
    }

    async handleDiscardDraft() {
        try {
            await discardEnquiry({ enquiryId: this.draft.enquiryId });
            this.draft = { ...this.draft, status: 'Discarded', canApply: false };
            await this.reloadHousehold();
        } catch (err) {
            this.toast('Could not discard', this.errorText(err), 'error');
        }
    }

    handleOpenApplied() {
        if (this.draft && this.draft.appliedRecordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: this.draft.appliedRecordId, actionName: 'view' }
            });
        }
    }

    handleProfileField(event) {
        const key = event.target.dataset.key;
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.profileDraft = { ...this.profileDraft, [key]: value };
    }

    handleToggleProfileEdit() {
        this.editingProfile = !this.editingProfile;
        this.profileDraft = {};
    }

    async handleSaveProfile() {
        const p = this.profile;
        const d = this.profileDraft;
        const pick = (k, fallback) => (d[k] !== undefined ? d[k] : fallback);
        this.savingProfile = true;
        try {
            await saveProfile({
                accountId: this.household.accountId,
                profileJson: JSON.stringify({
                    visitFrequency: pick('visitFrequency', p.visitFrequency) || null,
                    heardAbout: pick('heardAbout', p.heardAbout) || null,
                    interests: [...(pick('interests', p.interests) || [])],
                    preferredContact: pick('preferredContact', p.preferredContact) || null,
                    schoolDaycare: pick('schoolDaycare', p.schoolDaycare) || null
                })
            });
            this.profileDraft = {};
            this.editingProfile = false;
            this.toast('Profile saved', 'Segments updated.', 'success');
            await this.reloadHousehold();
        } catch (err) {
            this.toast('Could not save profile', this.errorText(err), 'error');
        } finally {
            this.savingProfile = false;
        }
    }

    async loadVisit(accountId) {
        this.loadingVisit = true;
        this.visit = undefined;
        try {
            this.visit = await getVisitSummary({ accountId });
        } catch (err) {
            this.visit = { source: 'Unavailable', note: this.errorText(err), visitsThisYear: 0, spend12Months: 0 };
        } finally {
            this.loadingVisit = false;
        }
    }

    async handleAsk() {
        this.asking = true;
        this.deskError = undefined;
        try {
            const res = await askDesk({
                accountId: this.household.accountId,
                keys: this.selectedKeys,
                customQuestion: this.customQuestion.trim() || null,
                focusRecordId: this.focusRecordId || null
            });
            if (!res.ok) {
                this.deskError = res.error;
                this.deskAnswers = [];
            } else {
                this.deskAnswers = res.answers.map((a) => ({ ...a, outcome: null }));
                this.selectedKeys = [];
                this.customQuestion = '';
                await this.reloadHousehold();
            }
        } catch (e) {
            this.deskError = this.errorText(e);
        } finally {
            this.asking = false;
        }
    }

    async handleOutcome(event) {
        const id = event.currentTarget.dataset.id;
        const outcome = event.currentTarget.dataset.outcome;
        try {
            await markDeskOutcome({ deskQuestionId: id, outcome });
            this.deskAnswers = this.deskAnswers.map((a) =>
                a.deskQuestionId === id ? { ...a, outcome: outcome === 'resolved' ? 'Resolved' : 'Escalated' } : a
            );
            await this.reloadHousehold();
        } catch (e) {
            this.toast('Could not save', this.errorText(e), 'error');
        }
    }

    async handleGetInsights() {
        this.loadingInsights = true;
        try {
            const res = await getInsights({ accountId: this.household.accountId });
            this.insights = res;
            if (!res.ok) {
                this.toast('AI response blocked', res.error, 'warning');
            }
        } catch (e) {
            this.toast('Insights failed', this.errorText(e), 'error');
        } finally {
            this.loadingInsights = false;
        }
    }

    async handleCreateTask(event) {
        const key = event.currentTarget.dataset.key;
        const t = this.insightTasks.find((x) => x.key === key);
        if (!t) {
            return;
        }
        try {
            await createTask({
                accountId: this.household.accountId,
                subject: t.subject,
                reason: t.reason,
                dueInDays: t.dueInDays,
                relatedRecordId: t.relatedRecordId,
                logId: this.insights.logId
            });
            this.removeSuggestion(key);
            this.toast('Task created', t.subject, 'success');
            await this.reloadHousehold();
        } catch (e) {
            this.toast('Could not create task', this.errorText(e), 'error');
        }
    }

    handleDismissTask(event) {
        this.removeSuggestion(event.currentTarget.dataset.key);
    }

    removeSuggestion(key) {
        const index = Number(key.substring(1));
        const next = [...this.insights.suggestedTasks];
        next.splice(index, 1);
        this.insights = { ...this.insights, suggestedTasks: next };
    }

    handleNoteInput(event) {
        this.noteText = event.target.value || '';
    }

    handleTeamMember(event) {
        this.noteTeamMember = event.detail.value;
    }

    async handleSaveNote() {
        this.savingNote = true;
        try {
            await addNote({
                accountId: this.household.accountId,
                contactId: this.household.primaryContactId,
                text: this.noteText.trim(),
                teamMember: this.noteTeamMember
            });
            this.noteText = '';
            this.toast('Note saved', 'Added to staff notes.', 'success');
            await this.reloadHousehold();
        } catch (e) {
            this.toast('Could not save note', this.errorText(e), 'error');
        } finally {
            this.savingNote = false;
        }
    }

    handleOpenRecord(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, actionName: 'view' }
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorText(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Unknown error';
    }
}
